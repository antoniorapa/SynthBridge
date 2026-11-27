import functools
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd


def _log(msg: str, info: Optional[Dict[str, Any]] = None) -> None:
    print(msg, flush=True)
    if isinstance(info, dict):
        log_file = info.get("log_path") or info.get("log_file")
        if log_file:
            try:
                p = Path(log_file)
                p.parent.mkdir(parents=True, exist_ok=True)
                with open(p, "a", encoding="utf-8") as f:
                    f.write(msg.rstrip() + "\n")
            except Exception:
                pass


def _patch_dense_to_sparse(info: Optional[Dict[str, Any]] = None) -> None:
    """Versione out-of-place di dense_to_sparse per evitare il RuntimeError in backward()."""
    import torch

    def _safe_dense_to_sparse(adj):
        if adj.dim() == 3:
            idx = adj.nonzero(as_tuple=False).t()
            b, row, col = idx[0], idx[1], idx[2]
            edge_attr = adj[b, row, col]
            offset = b * adj.size(1)
            return torch.stack([row + offset, col + offset], dim=0), edge_attr
        idx = adj.nonzero(as_tuple=False).t()
        return idx, adj[idx[0], idx[1]]

    try:
        import goggle.model.GraphInputProcessor as _gip_mod  # type: ignore

        _gip_mod.dense_to_sparse = _safe_dense_to_sparse
        _log("[GOGGLE] Patch out-of-place applicata a dense_to_sparse.", info)
    except Exception:
        pass


def _fallback_msg_agg(module, edge_index, args, kwargs):
    import torch

    x = args[0] if args else kwargs.get("x")
    ew = kwargs.get("edge_weight")
    if ew is None and len(args) > 1 and isinstance(args[1], torch.Tensor) and args[1].ndim == 1:
        ew = args[1]

    row, col = edge_index[0], edge_index[1]
    x_j = x.index_select(0, col)
    msg_kw = {k: v for k, v in kwargs.items() if k not in ("edge_weight", "size")}
    if ew is not None:
        msg_kw["edge_weight"] = ew

    try:
        out_msg = module.message(x_j=x_j, **msg_kw)
    except TypeError:
        try:
            out_msg = module.message(x_j)
        except TypeError:
            out_msg = x_j * ew.view(-1, 1) if ew is not None else x_j

    if ew is not None and "edge_weight" not in msg_kw:
        out_msg = out_msg * ew.view(-1, 1)

    try:
        out_agg = module.aggregate(out_msg, row, dim_size=x.size(0))
    except TypeError:
        out_agg = torch.zeros_like(x).index_add(0, row, out_msg)

    try:
        return module.update(out_agg)
    except TypeError:
        return out_agg


def _call_propagate_safely(fn, edge_index, args, kwargs, module=None):
    try:
        return fn(edge_index, *args, **kwargs)
    except (TypeError, UnboundLocalError) as exc:
        if "edge_weight" not in str(exc):
            raise
        kw_clean = {k: v for k, v in kwargs.items() if k != "edge_weight"}
        for a in (args, args[:-1] if args else ()):
            try:
                return fn(edge_index, *a, **kw_clean)
            except (TypeError, UnboundLocalError):
                continue
        if module is not None and hasattr(module, "message") and hasattr(module, "aggregate"):
            return _fallback_msg_agg(module, edge_index, args, kwargs)
        raise


def _patch_pyg(model=None, info: Optional[Dict[str, Any]] = None) -> None:
    try:
        from torch_geometric.nn.conv import MessagePassing  # type: ignore
    except Exception:
        return

    if not getattr(MessagePassing, "_sb_patched", False):
        orig = MessagePassing.propagate

        @functools.wraps(orig)
        def _guarded(self, edge_index, *args, **kwargs):
            return _call_propagate_safely(
                lambda ei, *a, **kw: orig(self, ei, *a, **kw),
                edge_index,
                args,
                kwargs,
                self,
            )

        MessagePassing.propagate = _guarded  # type: ignore
        MessagePassing._sb_patched = True  # type: ignore
        _log("[GOGGLE] Patch PyG MessagePassing.propagate applicata.", info)

    if model is not None:
        count = 0
        for mod in model.modules():
            if isinstance(mod, MessagePassing) and not getattr(mod.propagate, "_sb_inst", False):
                orig_inst = mod.propagate

                @functools.wraps(orig_inst)
                def _inst(edge_index, *args, _fn=orig_inst, _m=mod, **kwargs):
                    return _call_propagate_safely(_fn, edge_index, args, kwargs, _m)

                _inst._sb_inst = True  # type: ignore
                mod.propagate = _inst  # type: ignore
                count += 1
        if count:
            _log(f"[GOGGLE] Protetti {count} layer MessagePassing nel decoder.", info)


def _extract_loss_tensor(loss_out: Any):
    import torch

    if isinstance(loss_out, torch.Tensor):
        return loss_out
    if isinstance(loss_out, (tuple, list)):
        for item in loss_out:
            if isinstance(item, torch.Tensor) and item.requires_grad:
                return item
        for item in loss_out:
            if isinstance(item, torch.Tensor):
                return item
    if isinstance(loss_out, dict):
        for v in loss_out.values():
            if isinstance(v, torch.Tensor):
                return v
    raise TypeError(f"Loss non valida: {type(loss_out)}")


def _snap_calibrated(synth_vals: np.ndarray, ref_codes: np.ndarray) -> np.ndarray:
    unique_vals, counts = np.unique(np.asarray(ref_codes, dtype=np.int64), return_counts=True)
    if len(unique_vals) <= 1:
        return np.full(len(synth_vals), int(unique_vals[0]) if len(unique_vals) else 0, dtype=np.int64)
    cum_probs = np.cumsum(counts.astype(np.float64) / counts.sum())[:-1]
    bins = np.clip(np.digitize(synth_vals, np.quantile(synth_vals, cum_probs)), 0, len(unique_vals) - 1)
    return unique_vals[bins].astype(np.int64)


def _prepare_input(df: pd.DataFrame) -> Tuple[pd.DataFrame, List[str], Dict[str, Any]]:
    active_cols, const_map, col_specs, prepared = [], {}, {}, {}

    for col in df.columns:
        ser = df[col]
        if ser.astype(str).str.match(r"^cat_-?\d+$", na=False).any():
            num = pd.to_numeric(ser.astype(str).str.extract(r"^cat_(-?\d+)$")[0], errors="coerce")
            valid = num.dropna().astype(int).to_numpy()
            fb = int(pd.Series(valid).mode().iloc[0]) if len(valid) else 0
            codes = num.fillna(fb).astype(int).to_numpy()
            uniq = np.unique(codes)
            if len(uniq) <= 1:
                const_map[col] = ("cat_prefix", int(uniq[0]) if len(uniq) else fb)
                continue
            mu, sd = float(codes.mean()), float(codes.std()) or 1.0
            active_cols.append(col)
            col_specs[col] = {"kind": "cat_prefix", "raw_codes": codes, "mu": mu, "sd": sd}
            prepared[col] = ((codes - mu) / sd).astype(np.float32)

        elif not pd.api.types.is_numeric_dtype(ser):
            s_vals = ser.fillna("__MISSING__").astype(str).to_numpy()
            cats = sorted(np.unique(s_vals).tolist())
            if len(cats) <= 1:
                const_map[col] = ("labels", cats[0] if cats else "")
                continue
            mapping = {c: i for i, c in enumerate(cats)}
            codes = np.array([mapping[v] for v in s_vals], dtype=np.int64)
            mu, sd = float(codes.mean()), float(codes.std()) or 1.0
            active_cols.append(col)
            col_specs[col] = {"kind": "labels", "raw_codes": codes, "labels": cats, "mu": mu, "sd": sd}
            prepared[col] = ((codes - mu) / sd).astype(np.float32)

        else:
            s_num = pd.to_numeric(ser, errors="coerce").replace([np.inf, -np.inf], np.nan)
            valid = s_num.dropna().to_numpy(dtype=np.float64)
            vals = s_num.fillna(float(np.median(valid)) if len(valid) else 0.0).to_numpy(dtype=np.float64)
            if len(np.unique(vals)) <= 1:
                const_map[col] = ("numeric", float(vals[0]) if len(vals) else 0.0)
                continue
            is_int = bool(np.all(np.isclose(vals, np.rint(vals))))
            is_disc = len(np.unique(vals)) <= 10 and is_int
            mu, sd = float(vals.mean()), float(vals.std()) or 1.0
            active_cols.append(col)
            col_specs[col] = {
                "kind": "discrete_num" if is_disc else "continuous",
                "raw_codes": np.rint(vals).astype(np.int64) if is_disc else None,
                "min_val": float(vals.min()),
                "max_val": float(vals.max()),
                "is_int": is_int,
                "mu": mu,
                "sd": sd,
            }
            prepared[col] = ((vals - mu) / sd).astype(np.float32)

    df_train = pd.DataFrame(prepared, index=df.index) if active_cols else pd.DataFrame(index=df.index)
    return df_train, active_cols, {"const_map": const_map, "col_specs": col_specs}


def _postprocess(
    df_std: pd.DataFrame,
    orig_cols: List[str],
    active_cols: List[str],
    meta: Dict[str, Any],
) -> pd.DataFrame:
    n_out = len(df_std)
    out: Dict[str, Any] = {}

    for col, (kind, val) in meta["const_map"].items():
        if kind == "cat_prefix":
            out[col] = [f"cat_{int(val)}"] * n_out
        elif kind == "labels":
            out[col] = [val] * n_out
        else:
            out[col] = np.full(n_out, float(val), dtype=np.float64)

    for col in active_cols:
        spec = meta["col_specs"][col]
        raw = pd.to_numeric(df_std[col], errors="coerce").to_numpy(dtype=np.float64)
        fin = raw[np.isfinite(raw)]
        raw = np.where(np.isfinite(raw), raw, float(np.median(fin)) if len(fin) else 0.0)
        syn_sd = float(raw.std())
        normed = (raw - raw.mean()) / syn_sd if syn_sd > 1e-8 else (raw - raw.mean())
        rescaled = normed * spec["sd"] + spec["mu"]

        kind = spec["kind"]
        if kind == "cat_prefix":
            out[col] = [f"cat_{int(c)}" for c in _snap_calibrated(rescaled, spec["raw_codes"])]
        elif kind == "labels":
            labels = spec["labels"]
            out[col] = [
                labels[min(max(int(i), 0), len(labels) - 1)]
                for i in _snap_calibrated(rescaled, spec["raw_codes"])
            ]
        elif kind == "discrete_num":
            out[col] = _snap_calibrated(rescaled, spec["raw_codes"]).astype(np.float64)
        else:
            clipped = np.clip(rescaled, spec["min_val"], spec["max_val"])
            out[col] = np.rint(clipped) if spec["is_int"] else clipped

    df_out = pd.DataFrame(out)
    for c in orig_cols:
        if c not in df_out.columns:
            df_out[c] = 0.0
    return df_out[orig_cols]


def _train_and_sample(
    df_train: pd.DataFrame,
    n_rows: int,
    params: Dict[str, Any],
    info: Optional[Dict[str, Any]],
) -> pd.DataFrame:
    import torch

    if df_train.shape[1] == 0:
        return pd.DataFrame(index=range(n_rows))

    algo_dir = Path(__file__).resolve().parent
    if str(algo_dir) not in sys.path:
        sys.path.insert(0, str(algo_dir))

    _patch_pyg(info=info)

    from goggle.model.Goggle import Goggle  # type: ignore

    try:
        from goggle.model.GoggleLoss import GoggleLoss  # type: ignore
    except Exception:
        GoggleLoss = None

    _patch_pyg(info=info)
    _patch_dense_to_sparse(info)

    seed = int(params.get("seed", 42))
    np.random.seed(seed)
    torch.manual_seed(seed)

    epochs = int(params.get("epochs", params.get("n_epochs", 80)))
    batch_size = max(1, min(int(params.get("batch_size", 64)), len(df_train)))
    lr = float(params.get("learning_rate", params.get("lr", 5e-3)))
    weight_decay = float(params.get("weight_decay", 1e-4))
    graph_lambda = float(params.get("graph_lambda", 1e-2))
    encoder_dim = int(params.get("encoder_dim", 64))
    decoder_dim = int(params.get("decoder_dim", 64))
    threshold = float(params.get("threshold", 0.1))
    decoder_arch = str(params.get("decoder_arch", "het")).lower()
    patience = int(params.get("patience", 15))

    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    corr = np.abs(df_train.corr().fillna(0.0).to_numpy(dtype=np.float32))
    np.fill_diagonal(corr, 0.0)
    graph_prior = torch.tensor(corr, dtype=torch.float32, device=device)

    model = None
    used_arch = decoder_arch
    for arch in ([decoder_arch] if decoder_arch == "gcn" else [decoder_arch, "gcn"]):
        for kw in (
            dict(
                input_dim=df_train.shape[1],
                encoder_dim=encoder_dim,
                decoder_dim=decoder_dim,
                threshold=threshold,
                decoder_arch=arch,
                graph_prior=graph_prior,
                device=str(device),
            ),
            dict(
                input_dim=df_train.shape[1],
                encoder_dim=encoder_dim,
                decoder_dim=decoder_dim,
                threshold=threshold,
                decoder_arch=arch,
                device=str(device),
            ),
            dict(
                input_dim=df_train.shape[1],
                encoder_dim=encoder_dim,
                decoder_dim=decoder_dim,
            ),
        ):
            try:
                model = Goggle(**kw).to(device)
                used_arch = arch
                break
            except Exception:
                continue
        if model is not None:
            break

    _patch_pyg(model=model, info=info)
    _log(
        f"[GOGGLE] Architettura: {used_arch} ({type(model.decoder).__name__}) | "
        f"epochs={epochs} | batch={batch_size} | lr={lr}",
        info,
    )

    x_tensor = torch.tensor(df_train.to_numpy(dtype=np.float32), dtype=torch.float32, device=device)
    optimizer = torch.optim.Adam(model.parameters(), lr=lr, weight_decay=weight_decay)

    criterion = None
    if GoggleLoss is not None:
        for kw in ({"graph_lambda": graph_lambda}, {"lam": graph_lambda}, {}):
            try:
                criterion = GoggleLoss(**kw)
                break
            except TypeError:
                continue

    best_loss, best_state, no_improve = float("inf"), None, 0
    min_ep = min(20, max(5, epochs // 3))
    n_samples = len(df_train)
    t0 = time.time()

    model.train()
    for ep in range(epochs):
        perm = torch.randperm(n_samples, device=device)
        ep_loss, n_b = 0.0, 0
        for start in range(0, n_samples, batch_size):
            xb = x_tensor[perm[start : start + batch_size]]
            optimizer.zero_grad()
            x_hat, adj, mu_z, logvar_z = model(xb, ep)
            if criterion is not None:
                try:
                    raw_loss = criterion(x_hat, xb, mu_z, logvar_z, adj)
                except TypeError:
                    raw_loss = criterion(xb, x_hat, adj, mu_z, logvar_z)
                loss = _extract_loss_tensor(raw_loss)
            else:
                loss = torch.nn.functional.mse_loss(x_hat, xb)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), max_norm=5.0)
            optimizer.step()
            ep_loss += float(loss.detach().cpu().item())
            n_b += 1

        mean_loss = ep_loss / max(1, n_b)
        if (ep + 1) == 1 or (ep + 1) % 5 == 0 or (ep + 1) == epochs:
            elapsed = time.time() - t0
            _log(f"[GOGGLE] Epoca {ep + 1}/{epochs} | loss={mean_loss:.4f} | tempo={elapsed:.1f}s", info)

        if np.isfinite(mean_loss):
            if mean_loss < best_loss - 1e-5:
                best_loss = mean_loss
                best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
                no_improve = 0
            else:
                no_improve += 1
                if patience > 0 and no_improve >= patience and (ep + 1) >= min_ep:
                    _log(
                        f"[GOGGLE] Early stopping all'epoca {ep + 1}/{epochs} (best_loss={best_loss:.4f}).",
                        info,
                    )
                    break

    if best_state is not None:
        model.load_state_dict({k: v.to(device) for k, v in best_state.items()})

    _log(
        f"[GOGGLE] Training terminato in {time.time() - t0:.1f}s. Campionamento di {n_rows} righe (chunk=128)...",
        info,
    )
    model.eval()
    chunks, rem = [], n_rows
    while rem > 0:
        cur = min(128, rem)
        with torch.no_grad():
            s = model.sample(cur)
            arr = s.detach().cpu().numpy() if hasattr(s, "detach") else np.asarray(s)
        chunks.append(np.asarray(arr, dtype=np.float64)[:cur])
        rem -= cur

    synth_arr = np.vstack(chunks)[:n_rows]
    _log(f"[GOGGLE] Campionamento completato ({len(synth_arr)} righe).", info)
    return pd.DataFrame(synth_arr, columns=df_train.columns)


def generate(
    data: pd.DataFrame,
    n_rows: int,
    params: Optional[Dict[str, Any]] = None,
    info: Optional[Dict[str, Any]] = None,
) -> pd.DataFrame:
    if params is None:
        params = {}
    if not isinstance(data, pd.DataFrame):
        data = pd.DataFrame(data)
    if data.empty:
        raise ValueError("Il DataFrame 'data' passato a generate() è vuoto.")

    target_rows = int(n_rows) if n_rows is not None else len(data)
    orig_cols = list(data.columns)
    df_train, active_cols, meta = _prepare_input(data)
    _log(
        f"[GOGGLE] Input: {len(data)}x{len(orig_cols)} "
        f"(attive={len(active_cols)}, costanti={len(meta['const_map'])}) -> {target_rows} righe.",
        info,
    )

    df_synth_std = _train_and_sample(df_train, target_rows, params, info)
    return _postprocess(df_synth_std, orig_cols, active_cols, meta)