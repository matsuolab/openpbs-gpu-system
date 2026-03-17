"""Simple Transformer training example on synthetic data."""

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset
import time
import os


class SimpleTransformer(nn.Module):
    def __init__(self, vocab_size=10000, d_model=256, nhead=8, num_layers=4, dim_ff=1024):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, d_model)
        self.pos_embedding = nn.Embedding(512, d_model)
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=d_model, nhead=nhead, dim_feedforward=dim_ff, batch_first=True
        )
        self.transformer = nn.TransformerEncoder(encoder_layer, num_layers=num_layers)
        self.fc = nn.Linear(d_model, vocab_size)

    def forward(self, x):
        seq_len = x.size(1)
        positions = torch.arange(seq_len, device=x.device).unsqueeze(0)
        x = self.embedding(x) + self.pos_embedding(positions)
        x = self.transformer(x)
        return self.fc(x)


def main():
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")
    if device.type == "cuda":
        print(f"GPU: {torch.cuda.get_device_name(0)}")
        print(f"Memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")

    # Hyperparameters
    vocab_size = 10000
    seq_len = 128
    batch_size = int(os.environ.get("BATCH_SIZE", "64"))
    num_epochs = int(os.environ.get("EPOCHS", "5"))
    lr = float(os.environ.get("LR", "3e-4"))
    num_samples = 10000

    print(f"\nConfig: epochs={num_epochs}, batch_size={batch_size}, lr={lr}")
    print(f"Data: {num_samples} samples, seq_len={seq_len}, vocab_size={vocab_size}")

    # Synthetic data: next-token prediction
    data = torch.randint(0, vocab_size, (num_samples, seq_len + 1))
    inputs = data[:, :-1]
    targets = data[:, 1:]
    dataset = TensorDataset(inputs, targets)
    loader = DataLoader(dataset, batch_size=batch_size, shuffle=True)

    # Model
    model = SimpleTransformer(vocab_size=vocab_size).to(device)
    param_count = sum(p.numel() for p in model.parameters())
    print(f"Model: {param_count / 1e6:.1f}M parameters\n")

    optimizer = torch.optim.AdamW(model.parameters(), lr=lr)
    criterion = nn.CrossEntropyLoss()

    # Train
    for epoch in range(num_epochs):
        model.train()
        total_loss = 0
        start = time.time()

        for batch_idx, (x, y) in enumerate(loader):
            x, y = x.to(device), y.to(device)
            logits = model(x)
            loss = criterion(logits.view(-1, vocab_size), y.view(-1))

            optimizer.zero_grad()
            loss.backward()
            optimizer.step()
            total_loss += loss.item()

        elapsed = time.time() - start
        avg_loss = total_loss / len(loader)
        samples_per_sec = num_samples / elapsed
        print(f"Epoch {epoch+1}/{num_epochs}  loss={avg_loss:.4f}  "
              f"time={elapsed:.1f}s  samples/s={samples_per_sec:.0f}")

    print("\nTraining complete!")
    if device.type == "cuda":
        print(f"Peak GPU memory: {torch.cuda.max_memory_allocated() / 1e9:.2f} GB")


if __name__ == "__main__":
    main()
