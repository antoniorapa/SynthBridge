import json
import os
import traceback
import numpy as np
import pandas as pd
import torch
from sklearn.impute import SimpleImputer
from sklearn.preprocessing import OneHotEncoder, StandardScaler

import goggle.model.GraphInputProcessor as _gip_mod
from goggle.model.Goggle import Goggle
from goggle.model.GoggleLoss import GoggleLoss
from goggle.model.RGCNConv import RGCNConv as _GoggleRGCNConv


# ==============================================================================
# 1. PATCH IN MEMORIA (senza toccare alcun file originale di GOGGLE)
# ==============================================================================
def _patched_rgcn_forward(self, x, edge_index, edge_type=None, edge_weight=None):
    """
    Sostituisce RGCNConv.forward in puro PyTorch (index_add), evitando
    MessagePassing.propagate(..., edge_weight=...) su PyTorch Geometric 2.x.
    """
    x_l = x[0] if isinstance(x, tuple) else x
    if x_l is None:
        x_l = torch.arange(self.in_channels_l, device=self.weight.device)
    x_r = x[1] if isinstance(x, tuple) else x_l

    num_nodes = x_r.size(0)
    out = torch.zeros(num_nodes, self.out_channels, device=x_r.device, dtype=x_l.dtype)

    weight = self.weight
    if self.num_bases is not None:
        weight = (self.comp @ weight.view(self.num_bases, -1)).view(
            self.num_relations, self.in_channels_l, self.out_channels
        )

    if edge_type is not None and edge_type.numel() > 0:
        for rel in torch.unique(edge_type).tolist():
            mask = edge_type == rel
            src = edge_index[0, mask]
            dst = edge_index[1, mask]
            if src.numel() == 0:
                continue

            msg = x_l[src]
            if edge_weight is not None:
                msg = msg * edge_weight[mask].view(-1, 1)

            h = torch.zeros(num_nodes, x_l.size(1), device=x_l.device, dtype=x_l.dtype)
            h = h.index_add(0, dst, msg)

            if getattr(self, "aggr", "mean") == "mean":
                deg = torch.zeros(num_nodes, 1, device=x_l.device, dtype=x_l.dtype)
                ones = torch.ones((dst.numel(), 1), device=x_l.device, dtype=x_l.dtype)
                deg = deg.index_add(0, dst, ones)
                h = h / deg.clamp(min=1.0)

            out = out + (h @ weight[rel])

    if self.root is not None:
        out = out + (self.root[x_r] if x_r.dtype == torch.long else x_r @ self.root)

    if self.bias is not None:
        out = out + self.bias

    return out


def _safe_dense_to_sparse(adj):
    """
    Converte una matrice di adiacenza densa in formato sparso senza mutazioni
    in-place sugli indici, evitando errori in backward() su PyTorch 2.x.
    """
    if adj.dim() == 3:
        idx = adj.nonzero(as_tuple=False).t()
        b, row, col = idx[0], idx[1], idx[2]
        edge_attr = adj[b, row, col]
        offset = b * adj.size(1)
        edge_index = torch.stack([row + offset, col + offset], dim=0)
        return edge_index, edge_attr
    idx = adj.nonzero(as_tuple=False).t()
    return idx, adj[idx[0], idx[1]]


_GoggleRGCNConv.forward = _patched_rgcn_forward
_gip_mod.dense_to_sparse = _safe_dense_to_sparse


# ==============================================================================
# 2. ADAPTER UNIVERSALE DEFINITIVO PER GOGGLE
# ==============================================================================
class GoggleAdapter:
    def __init__(
        self,
        epochs: int = 50,
        batch_size: int = 16,
        lr: float = 5e-3,
        threshold: float = 0.10,
        decoder_arch: str = "het",
        encoder_dim: int = 64,
        decoder_dim: int = 64,
        patience: int = 10,
        use_graph_prior: bool = True,
        clip_to_real_bounds: bool = True,
        quantile_match: bool = True,
        seed: int = 42,
        device: str = None,
    ):
        self.epochs = int(epochs)
        self.batch_size = int(batch_size)
        self.lr = float(lr)
        self.threshold = float(threshold)
        self.decoder_arch = decoder_arch
        self.encoder_dim = int(encoder_dim)
        self.decoder_dim = int(decoder_dim)
        self.patience = int(patience)
        self.use_graph_prior = bool(use_graph_prior)
        self.clip_to_real_bounds = bool(clip_to_real_bounds)
        self.quantile_match = bool(quantile_match)
        self.seed = int(seed)
        self.device = device or ("cuda" if torch.cuda.is_available() else "cpu")

        self.columns_ = []
        self.const_cols_ = {}
        self.num_cols_ = []
        self.int_cols_ = []
        self.bin_cols_ = []
        self.bin_probs_ = {}
        self.cat_cols_ = []
        self.real_bounds_ = {}
        self.real_sorted_ = {}
        self.num_imputer_ = None
        self.cat_imputer_ = None
        self.scaler_ = None
        self.encoder_ = None
        self.model_ = None

    def _set_seed(self):
        np.random.seed(self.seed)
        torch.manual_seed(self.seed)
        if torch.cuda.is_available():
            torch.cuda.manual_seed_all(self.seed)

    def _prepare_input(self, df: pd.DataFrame) -> np.ndarray:
        work = df.copy()
        for col in list(work.columns):
            if col.lower() in {"id", "index", "unnamed: 0"}:
                work.drop(columns=[col], inplace=True)

        self.columns_ = list(work.columns)
        self.const_cols_ = {}
        self.num_cols_ = []
        self.int_cols_ = []
        self.bin_cols_ = []
        self.bin_probs_ = {}
        self.cat_cols_ = []
        self.real_bounds_ = {}
        self.real_sorted_ = {}

        for col in self.columns_:
            s = work[col].dropna()
            # Colonne costanti o vuote: gestite separatamente per evitare varianza nulla
            if len(s) == 0:
                self.const_cols_[col] = 0
                continue
            if s.nunique(dropna=True) <= 1:
                self.const_cols_[col] = s.iloc[0]
                continue

            is_cat = (
                pd.api.types.is_bool_dtype(work[col])
                or pd.api.types.is_object_dtype(work[col])
                or isinstance(work[col].dtype, pd.CategoricalDtype)
            )
            if is_cat:
                self.cat_cols_.append(col)
            else:
                self.num_cols_.append(col)
                vals_real = s.to_numpy(dtype=np.float64)
                self.real_bounds_[col] = (float(vals_real.min()), float(vals_real.max()))
                self.real_sorted_[col] = np.sort(vals_real)

                uniq = set(np.unique(vals_real))
                if uniq.issubset({0.0, 1.0}):
                    self.bin_cols_.append(col)
                    self.int_cols_.append(col)
                    self.bin_probs_[col] = float(np.mean(vals_real))
                elif np.all(np.isclose(vals_real % 1, 0)):
                    self.int_cols_.append(col)

        blocks = []
        if self.num_cols_:
            self.num_imputer_ = SimpleImputer(strategy="median")
            num_imp = self.num_imputer_.fit_transform(work[self.num_cols_])
            self.scaler_ = StandardScaler()
            num_scaled = self.scaler_.fit_transform(num_imp)
            blocks.append(num_scaled)

        if self.cat_cols_:
            self.cat_imputer_ = SimpleImputer(strategy="most_frequent")
            cat_imp = self.cat_imputer_.fit_transform(work[self.cat_cols_].astype(str))
            self.encoder_ = OneHotEncoder(sparse_output=False, handle_unknown="ignore")
            cat_ohe = self.encoder_.fit_transform(cat_imp)
            blocks.append(cat_ohe)

        if not blocks:
            return np.empty((len(work), 0), dtype=np.float32)
        return np.hstack(blocks).astype(np.float32)

    def _build_prior(self, X_proc: np.ndarray):
        if not self.use_graph_prior or X_proc.shape[0] < 3 or X_proc.shape[1] < 2:
            return None
        with np.errstate(divide="ignore", invalid="ignore"):
            corr = np.corrcoef(X_proc, rowvar=False)
        corr = np.nan_to_num(corr, nan=0.0, posinf=0.0, neginf=0.0)
        prior = np.abs(corr).astype(np.float32)
        np.fill_diagonal(prior, 1.0)
        return torch.tensor(prior, dtype=torch.float32, device=self.device)

    def fit(self, df: pd.DataFrame):
        self._set_seed()
        X_proc = self._prepare_input(df)
        n_rows, input_dim = X_proc.shape

        if input_dim == 0:
            self.model_ = None
            return self

        eff_batch = min(self.batch_size, max(8, n_rows // 2))
        graph_prior = self._build_prior(X_proc)

        model = None
        used_arch = self.decoder_arch
        for arch in [self.decoder_arch, "sage", "gcn"]:
            try:
                model = Goggle(
                    input_dim=input_dim,
                    encoder_dim=self.encoder_dim,
                    decoder_dim=self.decoder_dim,
                    het_encoding=(arch == "het"),
                    threshold=self.threshold,
                    decoder_arch=arch,
                    graph_prior=graph_prior,
                    device=self.device,
                ).to(self.device)
                used_arch = arch
                break
            except Exception:
                continue

        if model is None:
            raise RuntimeError("Impossibile inizializzare il modello GOGGLE.")

        print(
            f"--- AVVIO GOGGLE ({used_arch.upper()} | Prior: {'ATTIVO' if graph_prior is not None else 'NO'}) "
            f"| {n_rows} righe, {input_dim} feature attive ({len(self.const_cols_)} costanti) ---",
            flush=True,
        )

        optimizer = torch.optim.Adam(model.parameters(), lr=self.lr)
        criterion = GoggleLoss()

        tensor_x = torch.tensor(X_proc, dtype=torch.float32, device=self.device)
        best_loss = float("inf")
        best_state = None
        no_improve = 0

        model.train()
        for epoch in range(self.epochs):
            perm = torch.randperm(n_rows, device=self.device)
            epoch_losses = []

            for start in range(0, n_rows, eff_batch):
                batch_idx = perm[start : start + eff_batch]
                batch_x = tensor_x[batch_idx]

                optimizer.zero_grad()
                x_hat, adj, mu_z, logvar_z = model(batch_x, epoch)
                loss_out = criterion(x_hat, batch_x, mu_z, logvar_z, adj)
                loss = loss_out[0] if isinstance(loss_out, tuple) else loss_out
                loss.backward()
                optimizer.step()
                epoch_losses.append(float(loss.detach().cpu().item()))

            mean_loss = float(np.mean(epoch_losses)) if epoch_losses else float("inf")
            if (epoch + 1) % 5 == 0 or epoch == 0:
                pct = int(((epoch + 1) / self.epochs) * 100)
                print(f"[progress] {pct}% Epoca {epoch + 1}/{self.epochs} - Loss: {mean_loss:.4f}", flush=True)

            if mean_loss < best_loss - 1e-5:
                best_loss = mean_loss
                best_state = {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}
                no_improve = 0
            else:
                no_improve += 1
                if no_improve >= self.patience:
                    print(f"Early stopping all'epoca {epoch + 1} (best loss: {best_loss:.4f})", flush=True)
                    break

        if best_state is not None:
            model.load_state_dict({k: v.to(self.device) for k, v in best_state.items()})

        self.model_ = model
        return self

    def _restore_dataframe(self, synth_np: np.ndarray, n_samples: int) -> pd.DataFrame:
        rng = np.random.default_rng(self.seed)
        out = {}
        pos = 0

        # 1. Colonne costanti ripristinate esattamente
        for col, const_val in self.const_cols_.items():
            out[col] = np.full(n_samples, const_val)

        # 2. Colonne numeriche (con quantile mapping / soglia calibrata)
        if self.num_cols_:
            n_num = len(self.num_cols_)
            num_inv = self.scaler_.inverse_transform(synth_np[:, pos : pos + n_num])
            pos += n_num

            for j, col in enumerate(self.num_cols_):
                vals = num_inv[:, j].astype(np.float64)

                if col in self.bin_cols_:
                    p_one = self.bin_probs_[col]
                    tie_noise = rng.normal(0.0, 1e-12, size=n_samples)
                    order = np.argsort(vals + tie_noise, kind="mergesort")
                    n_ones = int(round(p_one * n_samples))
                    bin_out = np.zeros(n_samples, dtype=int)
                    if n_ones > 0:
                        bin_out[order[-n_ones:]] = 1
                    vals = bin_out
                else:
                    if self.quantile_match and col in self.real_sorted_:
                        real_sorted = self.real_sorted_[col]
                        real_grid = np.linspace(0.0, 1.0, len(real_sorted), endpoint=True)
                        tie_noise = rng.normal(0.0, 1e-12, size=n_samples)
                        order = np.argsort(vals + tie_noise, kind="mergesort")
                        ranks = np.empty(n_samples, dtype=np.float64)
                        ranks[order] = np.arange(n_samples, dtype=np.float64)
                        u = (ranks + 0.5) / n_samples
                        vals = np.interp(u, real_grid, real_sorted)

                    if self.clip_to_real_bounds and col in self.real_bounds_:
                        lo, hi = self.real_bounds_[col]
                        vals = np.clip(vals, lo, hi)
                    if col in self.int_cols_:
                        vals = np.rint(vals).astype(int)

                out[col] = vals

        # 3. Colonne categoriche (argmax sui blocchi One-Hot)
        if self.cat_cols_:
            for col, cats in zip(self.cat_cols_, self.encoder_.categories_):
                k = len(cats)
                block = synth_np[:, pos : pos + k]
                pos += k
                idx = np.argmax(block, axis=1)
                out[col] = np.array(cats)[idx]

        df_out = pd.DataFrame(out)[self.columns_]

        # Garanzia finale: zero NA
        for col in df_out.columns:
            if df_out[col].isna().any():
                fill_val = (
                    df_out[col].mode().iloc[0]
                    if col in self.cat_cols_
                    else df_out[col].median()
                )
                df_out[col] = df_out[col].fillna(fill_val)
        return df_out

    def sample(self, n_samples: int) -> pd.DataFrame:
        n_samples = int(n_samples)
        if self.model_ is None:
            if self.const_cols_:
                return self._restore_dataframe(np.empty((n_samples, 0), dtype=np.float32), n_samples)
            raise RuntimeError("Chiama prima .fit(df) prima di .sample(n_samples).")

        self.model_.eval()
        synth_tensor = self.model_.sample(count=n_samples)
        synth_np = synth_tensor.detach().cpu().numpy().astype(np.float32)
        if synth_np.ndim == 1:
            synth_np = synth_np.reshape(1, -1)
        return self._restore_dataframe(synth_np[:n_samples], n_samples)


# ==============================================================================
# 3. ENTRY POINT PER SYNTHBRIDGE E USO STANDALONE
# ==============================================================================
def generate(data, n_rows, params=None, info=None):
    params = params or {}
    df_real = data if isinstance(data, pd.DataFrame) else pd.DataFrame(data)
    n_target = int(n_rows if n_rows is not None else len(df_real))

    adapter = GoggleAdapter(
        epochs=int(params.get("epochs", 50)),
        batch_size=int(params.get("batch_size", params.get("batch", 16))),
        lr=float(params.get("learning_rate", params.get("lr", 5e-3))),
        threshold=float(params.get("threshold", 0.10)),
        decoder_arch=str(params.get("decoder_arch", "het")),
        encoder_dim=int(params.get("encoder_dim", 64)),
        decoder_dim=int(params.get("decoder_dim", 64)),
        patience=int(params.get("patience", 10)),
        use_graph_prior=bool(params.get("use_graph_prior", True)),
        clip_to_real_bounds=bool(params.get("clip_to_real_bounds", True)),
        quantile_match=bool(params.get("quantile_match", True)),
        seed=int(params.get("seed", 42)),
    )
    adapter.fit(df_real)
    return adapter.sample(n_target)


def run_synthbridge_job(run_dir: str = "runs"):
    input_path = os.path.join(run_dir, "input.csv")
    job_path = os.path.join(run_dir, "job.json")
    synthetic_path = os.path.join(run_dir, "synthetic.csv")
    status_path = os.path.join(run_dir, "status.json")

    try:
        with open(job_path, "r", encoding="utf-8") as f:
            params = json.load(f)

        df_real = pd.read_csv(input_path)
        n_synth = int(params.get("n_samples", params.get("count", params.get("n_rows", len(df_real)))))
        df_syn = generate(df_real, n_synth, params=params, info=None)
        df_syn.to_csv(synthetic_path, index=False)

        with open(status_path, "w", encoding="utf-8") as f:
            json.dump({"status": "success", "rows": len(df_syn)}, f)
    except Exception as exc:
        with open(status_path, "w", encoding="utf-8") as f:
            json.dump(
                {"status": "error", "message": f"{exc}\n{traceback.format_exc()}"},
                f,
            )
        raise


if __name__ == "__main__":
    if os.path.exists(os.path.join("runs", "input.csv")) and os.path.exists(
        os.path.join("runs", "job.json")
    ):
        run_synthbridge_job("runs")