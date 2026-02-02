# Planter UNSW-NB15 BMv2

In-network ML classification for network intrusion detection using the [Planter](https://github.com/In-Network-Machine-Learning/Planter) methodology on BMv2 software switches.

## Overview

This project implements an in-network machine learning pipeline that:

1. Trains a Decision Tree on the [UNSW-NB15](https://research.unsw.edu.au/projects/unsw-nb15-dataset) dataset
2. Generates P4 match-action table entries
3. Deploys to BMv2 switches for line-rate classification

```
UNSW-NB15 Data → Train Tree → Generate P4 Tables → Deploy to BMv2
```

## Quick Start

### Prerequisites

- Python 3.9+ with [uv](https://github.com/astral-sh/uv)
- Docker Desktop

### Setup

```bash
# Install dependencies
uv sync

# Download UNSW-NB15 and place in data/
# https://research.unsw.edu.au/projects/unsw-nb15-dataset
```

### Run

```bash
# Demo (no BMv2 required)
uv run python -m src.demo

# Full pipeline: train model and generate P4 tables
uv run python -m src.train_model

# Deploy to BMv2
cd bmv2 && ./setup.sh setup
```

## BMv2 Deployment

The setup script handles everything: P4 compilation, container orchestration, networking, and table loading.

```
h1 (10.0.1.1) ←→ s1 ←→ s2 ←→ h2 (10.0.2.2)
                ↑         ↑
           ML classify  ML classify
```

```bash
cd bmv2

./setup.sh setup    # Full setup
./setup.sh test     # Verify connectivity
./setup.sh logs     # View ML classification logs
./setup.sh stop     # Stop containers
```

## Project Structure

```
├── src/                 # Python ML pipeline
│   ├── config.py        # Configuration
│   ├── demo.py          # Quick demo
│   ├── prepare_data.py  # Data preparation
│   └── train_model.py   # Training & P4 generation
├── p4/
│   └── ml_classifier.p4 # P4 program (routing + ML)
├── bmv2/                # BMv2 deployment
│   ├── setup.sh         # Main setup script
│   ├── docker-compose.yml
│   └── Dockerfiles/
├── data/                # UNSW-NB15 data (gitignored)
└── pyproject.toml
```

## How It Works

### Decision Trees → P4

- Each tree level maps to one pipeline stage
- Feature comparisons become match-action tables
- Integer-only operations for line-rate processing

### P4 Features

| Feature | P4 Source |
|---------|-----------|
| sttl | `hdr.ipv4.ttl` |
| sport | `hdr.tcp.srcPort` |
| dsport | `hdr.tcp.dstPort` |
| sbytes | `hdr.ipv4.totalLen` |

## References

- [Planter Paper](https://dl.acm.org/doi/10.1145/3452296.3472934) - "Seeding Trees Within Switches" (SIGCOMM'21)
- [UNSW-NB15 Dataset](https://research.unsw.edu.au/projects/unsw-nb15-dataset)
- [Related: FLIP4](https://github.com/In-Network-Machine-Learning/FLIP4), [P4Pir](https://github.com/In-Network-Machine-Learning/P4Pir)

## Future Work

See [MELHORIAS.md](MELHORIAS.md) for planned improvements.
