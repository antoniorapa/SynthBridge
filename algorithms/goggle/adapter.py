import torch
import pandas as pd
import numpy as np
from sklearn.preprocessing import LabelEncoder
from goggle.model.Goggle import Goggle
from goggle.model.GoggleLoss import GoggleLoss


def generate(data, n_rows, params, info):
    # 1. Estrazione parametri
    epochs = int(params.get("epochs", 10))
    batch_size = int(params.get("batch_size", 10))
    lr = float(params.get("learning_rate", 0.01))

    device = torch.device("cpu")

    # 2. Preprocessing: Trasformiamo le stringhe in numeri
    df_processed = data.copy()
    cat_cols = info.get("categorical_columns", [])
    encoders = {}

    for col in cat_cols:
        le = LabelEncoder()
        # Convertiamo la colonna testuale in interi (0, 1, 2...)
        df_processed[col] = le.fit_transform(df_processed[col].astype(str))
        encoders[col] = le

    # Riempiamo eventuali valori mancanti con 0 per evitare crash sui tensori
    df_processed = df_processed.fillna(0)

    # Creiamo il tensore per PyTorch (ora sono tutti numeri float32!)
    data_tensor = torch.tensor(df_processed.values, dtype=torch.float32).to(device)

    from torch.utils.data import DataLoader, TensorDataset
    dataset_torch = TensorDataset(data_tensor)
    dataloader = DataLoader(dataset_torch, batch_size=batch_size, shuffle=True, drop_last=False)

    # 3. Inizializzazione GOGGLE
    model = Goggle(
        input_dim=data.shape[1],
        encoder_dim=64,
        decoder_dim=64,
        threshold=0.1,
        decoder_arch="gcn",
        device="cpu"
    ).to(device)

    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    criterion = GoggleLoss()

    # 4. Addestramento
    model.train()
    total_steps = epochs * len(dataloader)
    current_step = 0

    for epoch in range(epochs):
        for batch in dataloader:
            x_batch = batch[0].to(device)
            optimizer.zero_grad()

            x_hat, adj, mu_z, logvar_z = model(x_batch, epoch)

            loss_output = criterion(x_hat, x_batch, mu_z, logvar_z, adj)
            loss = loss_output[0] if isinstance(loss_output, tuple) else loss_output

            loss.backward()
            optimizer.step()

            current_step += 1
            if "progress" in info and callable(info["progress"]):
                info["progress"](min(0.9, current_step / max(1, total_steps)), f"Epoca {epoch + 1}/{epochs}")

    # 5. Generazione e Postprocessing
    model.eval()
    synthetic_tensor = model.sample(count=n_rows)

    df_synthetic = pd.DataFrame(
        synthetic_tensor.detach().cpu().numpy(),
        columns=data.columns
    )

    # Ritraduciamo i numeri generati nelle categorie testuali originali
    for col in cat_cols:
        le = encoders[col]
        max_class = len(le.classes_) - 1
        # Arrotondiamo i valori generati (es. 1.2 diventa 1) per ricollegarli alla classe
        mapped = np.clip(np.round(df_synthetic[col].values), 0, max_class).astype(int)
        df_synthetic[col] = le.inverse_transform(mapped)

    if "progress" in info and callable(info["progress"]):
        info["progress"](1.0, "Completato")

    return df_synthetic