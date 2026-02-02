"""
Quick Demo: UNSW-NB15 to P4 with Planter Methodology
====================================================

Self-contained demonstration of the complete pipeline.
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
from sklearn.tree import DecisionTreeClassifier, export_text
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

from .config import Config, UNSW_COLUMNS


def main():
    """Run the demonstration."""
    print("=" * 70)
    print("Planter Demo: UNSW-NB15 In-Network ML Classification")
    print("=" * 70)
    
    config = Config()
    
    # Step 1: Load data
    print("\n[1/4] Loading UNSW-NB15 data...")
    df = _load_sample_data(config)
    if df is None:
        print("\nERROR: No data found. Please ensure UNSW-NB15 data is available.")
        print("See README.md for data setup instructions.")
        return 1
    
    print(f"  Loaded {len(df)} samples")
    
    # Step 2: Prepare features
    print("\n[2/4] Preparing features for P4...")
    X, y, features = _prepare_features(df, config)
    print(f"  Features: {features}")
    print(f"  Labels: Normal={sum(y==0)}, Attack={sum(y==1)}")
    
    # Step 3: Train model
    print("\n[3/4] Training Decision Tree...")
    dt, X_test, y_test = _train_model(X, y, config)
    
    y_pred = dt.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    print(f"\n  Model Performance:")
    print(f"    Accuracy: {accuracy:.4f}")
    print(f"    Tree depth: {dt.get_depth()} (= P4 pipeline stages)")
    print(f"    Leaf nodes: {dt.get_n_leaves()} (= table entries)")
    
    print(f"\n  Classification Report:")
    print(classification_report(y_test, y_pred, target_names=["Normal", "Attack"]))
    
    # Step 4: Show P4 mapping
    print("\n[4/4] P4 Implementation Preview...")
    tree_text = export_text(dt, feature_names=features, max_depth=3)
    print(f"\n  Decision Tree (first 3 levels):")
    for line in tree_text.split("\n")[:15]:
        print(f"  {line}")
    
    _print_p4_summary(dt, features)
    
    print("\n" + "=" * 70)
    print("Demo Complete!")
    print("=" * 70)
    print("""
Next steps:
  uv run python -m src.train_model   # Train model and generate P4 tables

For BMv2 deployment:
  cd bmv2 && ./setup.sh setup        # Full setup (compile, start, configure)
""")
    return 0


def _load_sample_data(config: Config, max_rows: int = 100000) -> pd.DataFrame | None:
    """Load sample data for demo."""
    # Try combined CSV
    if config.unsw_combined_csv and config.unsw_combined_csv.exists():
        return pd.read_csv(config.unsw_combined_csv, nrows=max_rows, low_memory=False)
    
    # Try raw CSVs
    if config.unsw_csv_dir and config.unsw_csv_dir.exists():
        csv_files = list(config.unsw_csv_dir.glob("UNSW-NB15_*.csv"))
        if csv_files:
            df = pd.read_csv(csv_files[0], header=None, nrows=max_rows)
            df.columns = UNSW_COLUMNS[:len(df.columns)]
            return df
    
    return None


def _prepare_features(df: pd.DataFrame, config: Config) -> tuple:
    """Prepare features for P4."""
    # Select P4-compatible features that exist in the dataframe
    available = [f for f in config.p4_features if f in df.columns]
    
    # If not enough P4 features, use numeric columns
    if len(available) < 3:
        numeric = df.select_dtypes(include=[np.number]).columns
        available = [c for c in numeric if c not in ["Label", "attack_cat"]][:5]
    
    # Extract and convert to numeric
    X = df[available].copy()
    
    # Convert all columns to numeric, coercing errors to NaN
    for col in X.columns:
        X[col] = pd.to_numeric(X[col], errors="coerce")
    
    # Fill NaN and infinite values
    X = X.fillna(0).replace([np.inf, -np.inf], 0)
    
    # Remove any columns that are still not numeric
    numeric_cols = X.select_dtypes(include=[np.number]).columns.tolist()
    if len(numeric_cols) < len(X.columns):
        print(f"  Warning: Some columns could not be converted to numeric")
        X = X[numeric_cols]
        available = numeric_cols
    
    # Quantize to 8-bit
    for col in X.columns:
        col_min, col_max = X[col].min(), X[col].max()
        if col_max > col_min:
            X[col] = ((X[col] - col_min) / (col_max - col_min) * 255).astype(int)
        else:
            X[col] = 0
        X[col] = X[col].clip(0, 255)
    
    # Get labels (binary)
    if "attack_cat" in df.columns:
        y_raw = df["attack_cat"].fillna("Normal").astype(str).str.strip()
    elif "Label" in df.columns:
        y_raw = df["Label"].map({0: "Normal", 1: "Attack"}).fillna("Normal")
    else:
        raise ValueError("No label column found")
    
    y = (~y_raw.astype(str).str.contains("Normal", case=False, na=False)).astype(int)
    
    return X, y, list(X.columns)


def _train_model(X: pd.DataFrame, y: pd.Series, config: Config) -> tuple:
    """Train Decision Tree."""
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    
    dt = DecisionTreeClassifier(
        max_depth=4,  # Small for demo
        min_samples_leaf=100,
        random_state=42
    )
    dt.fit(X_train, y_train)
    
    return dt, X_test, y_test


def _print_p4_summary(dt: DecisionTreeClassifier, features: list) -> None:
    """Print P4 implementation summary."""
    print(f"\n  P4 Implementation Summary:")
    print(f"  " + "-" * 40)
    print(f"  Pipeline stages: {dt.get_depth()}")
    print(f"  Table entries: {dt.get_n_leaves()}")
    print(f"  Feature tables: {len(features)}")
    print(f"\n  Sample P4 table commands:")
    
    tree = dt.tree_
    for i, feat in enumerate(features[:3]):
        thresholds = set()
        for node in range(tree.node_count):
            if tree.feature[node] == i:
                thresholds.add(int(tree.threshold[node]))
        
        if thresholds:
            t = min(thresholds)
            print(f"    table_add ml_feature_{i} set_code_{i} 0->{t} => 0")
            print(f"    table_add ml_feature_{i} set_code_{i} {t+1}->255 => 1")


if __name__ == "__main__":
    sys.exit(main())
