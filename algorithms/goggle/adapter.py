import torch
import pandas as pd
import numpy as np
import copy
from sklearn.preprocessing import LabelEncoder, MinMaxScaler
from torch.utils.data import DataLoader, TensorDataset
from goggle.model.Goggle import Goggle
from goggle.model.GoggleLoss import GoggleLoss


def generate(data, n_rows, params, info):
    device = torch.device("cpu")

    # 1. PREPROCESSING: Label Encoding e Normalizzazione (per far studiare bene la rete)
    df_processed = data.copy()
    encoders = {}

    for col in df_processed.columns:
        if df_processed[col].dtype == 'object' or pd.api.types.is_categorical_dtype(df_processed[col]):
            le = LabelEncoder()
            df_processed[col] = le.fit_transform(df_processed[col].astype(str))
            encoders[col] = le

    df_processed = df_processed.apply(pd.to_numeric, errors='coerce').fillna(0).astype('float32')

    scaler = MinMaxScaler()
    df_scaled = pd.DataFrame(scaler.fit_transform(df_processed), columns=df_processed.columns)

    data_tensor = torch.tensor(df_scaled.values, dtype=torch.float32).to(device)
    dataset_torch = TensorDataset(data_tensor)

    # 2. HYPERPARAMETER TUNING RAPIDO
    hyper_grid = [
        {"lr": 0.01, "batch": 16},
        {"lr": 0.005, "batch": 16},
        {"lr": 0.05, "batch": 32}
    ]

    best_loss_overall = float('inf')
    best_params = hyper_grid[0]
    best_model_state = None

    print("\n--- AVVIO OTTIMIZZAZIONE AUTOMATICA GOGGLE ---")

    for idx, params_test in enumerate(hyper_grid):
        test_loader = DataLoader(dataset_torch, batch_size=params_test['batch'], shuffle=True, drop_last=False)
        test_model = Goggle(input_dim=data.shape[1], encoder_dim=64, decoder_dim=64, threshold=0.1, decoder_arch="gcn",
                            device="cpu").to(device)
        test_optimizer = torch.optim.Adam(test_model.parameters(), lr=params_test['lr'])
        test_criterion = GoggleLoss()

        patience = 10
        patience_counter = 0
        best_trial_loss = float('inf')
        trial_epochs = 200

        test_model.train()
        for epoch in range(trial_epochs):
            epoch_loss = 0.0
            for batch in test_loader:
                x_batch = batch[0].to(device)
                test_optimizer.zero_grad()
                x_hat, adj, mu_z, logvar_z = test_model(x_batch, epoch)
                loss_out = test_criterion(x_hat, x_batch, mu_z, logvar_z, adj)
                loss = loss_out[0] if isinstance(loss_out, tuple) else loss_out
                loss.backward()
                test_optimizer.step()
                epoch_loss += loss.item()

            avg_epoch_loss = epoch_loss / len(test_loader)

            if avg_epoch_loss < best_trial_loss:
                best_trial_loss = avg_epoch_loss
                patience_counter = 0
            else:
                patience_counter += 1

            if "progress" in info and callable(info["progress"]):
                try:
                    overall_progress = (idx + (epoch / trial_epochs)) / len(hyper_grid) * 0.9
                    info["progress"](overall_progress, f"Test {idx + 1}/{len(hyper_grid)} - Epoca {epoch + 1}")
                except PermissionError:
                    pass

            if patience_counter >= patience:
                break

        if best_trial_loss < best_loss_overall:
            best_loss_overall = best_trial_loss
            best_params = params_test
            best_model_state = copy.deepcopy(test_model.state_dict())

    # 3. GENERAZIONE DATI GREZZI DALLA RETE
    model = Goggle(input_dim=data.shape[1], encoder_dim=64, decoder_dim=64, threshold=0.1, decoder_arch="gcn",
                   device="cpu").to(device)
    model.load_state_dict(best_model_state)
    model.eval()

    synthetic_tensor_scaled = model.sample(count=n_rows)
    df_synthetic = pd.DataFrame(synthetic_tensor_scaled.detach().cpu().numpy(), columns=data.columns)

    # 4. POSTPROCESSING: QUANTILE MAPPING UNIVERSALE
    # (Ignoriamo i numeri sballati della rete e usiamo solo l'ordine per mapparli sui veri valori)
    for col in df_synthetic.columns:
        real_values = data[col].values

        # 1. Creiamo una distribuzione target perfetta basata sui dati reali
        target_distribution = np.random.choice(real_values, size=n_rows, replace=True)
        target_distribution.sort()

        # 2. Usiamo i dati generati da GOGGLE solo per stabilire il "ranking" (le correlazioni latenti)
        synth_values_with_noise = df_synthetic[col].values + np.random.normal(0, 1e-6, n_rows)
        sort_indices = np.argsort(synth_values_with_noise)

        # 3. Uniamo le due cose: applichiamo i veri valori secondo l'ordine di GOGGLE
        mapped_values = np.empty_like(target_distribution)
        mapped_values[sort_indices] = target_distribution

        # 4. Assegnazione finale con i tipi corretti
        if col in encoders or data[col].nunique() <= 5:
            df_synthetic[col] = mapped_values.astype(int)
        else:
            df_synthetic[col] = mapped_values.astype(float)

    if "progress" in info and callable(info["progress"]):
        try:
            info["progress"](1.0, "Completato")
        except PermissionError:
            pass

    return df_synthetic