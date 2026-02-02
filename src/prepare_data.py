"""Prepare UNSW-NB15 for Planter: load, quantize, split train/test."""

import json
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split

from .config import Config, UNSW_COLUMNS


def load_data(config: Config) -> tuple[pd.DataFrame, pd.Series]:
    """Load from combined CSV first, then raw UNSW-NB15_*.csv files."""
    print("Loading UNSW-NB15 data...")

    if config.unsw_combined_csv and config.unsw_combined_csv.exists():
        print(f"  Loading from CSV: {config.unsw_combined_csv}")
        df = pd.read_csv(config.unsw_combined_csv, low_memory=False)
        return _extract_features_labels(df, config)

    if config.unsw_csv_dir and config.unsw_csv_dir.exists():
        csv_files = sorted(config.unsw_csv_dir.glob("UNSW-NB15_*.csv"))
        if csv_files:
            print(f"  Loading from {len(csv_files)} CSV files...")
            dfs = []
            for csv_file in csv_files:
                df = pd.read_csv(csv_file, header=None, names=UNSW_COLUMNS, low_memory=False)
                dfs.append(df)
            df = pd.concat(dfs, ignore_index=True)
            return _extract_features_labels(df, config)
    
    raise FileNotFoundError(
        f"""
No UNSW-NB15 data found!

Please place your data in one of these locations:
  - {config.unsw_combined_csv}  (combined CSV)
  - {config.unsw_csv_dir}/UNSW-NB15_*.csv  (raw CSVs)

Download from: https://research.unsw.edu.au/projects/unsw-nb15-dataset
"""
    )


def _extract_features_labels(df: pd.DataFrame, config: Config) -> tuple[pd.DataFrame, pd.Series]:
    available = [f for f in config.p4_features if f in df.columns]
    if len(available) < 3:
        numeric = df.select_dtypes(include=[np.number]).columns
        available = [c for c in numeric if c not in ["Label", "attack_cat"]][:5]

    X = df[available].copy()
    for col in X.columns:
        X[col] = pd.to_numeric(X[col], errors="coerce")

    numeric_cols = X.select_dtypes(include=[np.number]).columns.tolist()
    X = X[numeric_cols]

    if "attack_cat" in df.columns:
        y = df["attack_cat"].fillna("Normal").astype(str).str.strip()
        y = y.replace("", "Normal")
    elif "Label" in df.columns:
        y = df["Label"].map({0: "Normal", 1: "Attack"}).fillna("Normal")
    else:
        raise ValueError("No label column found in dataset")
    
    return X, y


def quantize_features(X: pd.DataFrame, bits: int = 8) -> pd.DataFrame:
    """Min-max scale to [0, 2^bits-1] for P4 table lookups."""
    max_val = 2**bits - 1
    X_quant = X.copy()
    for col in X_quant.columns:
        X_quant[col] = pd.to_numeric(X_quant[col], errors="coerce")

    X_quant = X_quant.fillna(0)
    X_quant = X_quant.replace([np.inf, -np.inf], 0)
    
    for col in X_quant.columns:
        col_min, col_max = X_quant[col].min(), X_quant[col].max()
        if col_max > col_min:
            X_quant[col] = ((X_quant[col] - col_min) / (col_max - col_min) * max_val).astype(int)
        else:
            X_quant[col] = 0
        X_quant[col] = X_quant[col].clip(0, max_val)
    
    return X_quant


def prepare_dataset(config: Config) -> dict:
    X, y = load_data(config)
    print(f"  Loaded {len(X)} samples with {len(X.columns)} features")
    print(f"  Features: {list(X.columns)}")

    if config.binary_classification:
        y_binary = (~y.astype(str).str.contains("Normal", case=False, na=False)).astype(int)
        label_mapping = {"Normal": 0, "Attack": 1}
    else:
        unique_labels = sorted(y.unique())
        label_mapping = {label: i for i, label in enumerate(unique_labels)}
        y_binary = y.map(label_mapping)
    
    print(f"  Label distribution: {dict(y_binary.value_counts())}")

    print(f"  Quantizing features to {config.quantize_bits}-bit...")
    X_quant = quantize_features(X, config.quantize_bits)

    X_train, X_test, y_train, y_test = train_test_split(
        X_quant, y_binary,
        test_size=config.test_size,
        random_state=config.random_state,
        stratify=y_binary
    )
    
    print(f"  Train: {len(X_train)}, Test: {len(X_test)}")
    
    return {
        "X_train": X_train,
        "X_test": X_test,
        "y_train": y_train,
        "y_test": y_test,
        "features": list(X.columns),
        "label_mapping": label_mapping,
        "config": {
            "binary": config.binary_classification,
            "quantize_bits": config.quantize_bits,
            "num_classes": len(label_mapping),
        }
    }


def save_dataset(data: dict, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    train_df = data["X_train"].copy()
    train_df["label"] = data["y_train"].values
    train_df.to_csv(output_dir / "train.csv", index=False)
    
    test_df = data["X_test"].copy()
    test_df["label"] = data["y_test"].values
    test_df.to_csv(output_dir / "test.csv", index=False)

    metadata = {
        "features": data["features"],
        "label_mapping": data["label_mapping"],
        "config": data["config"],
        "train_samples": len(data["X_train"]),
        "test_samples": len(data["X_test"]),
    }
    
    with open(output_dir / "metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)
    
    print(f"  Saved dataset to {output_dir}")


def main():
    print("=" * 60)
    print("UNSW-NB15 Data Preparation for Planter")
    print("=" * 60)
    
    config = Config()
    data = prepare_dataset(config)
    save_dataset(data, config.data_dir)
    
    print("\nData preparation complete!")
    print(f"Output: {config.data_dir}")


if __name__ == "__main__":
    main()
