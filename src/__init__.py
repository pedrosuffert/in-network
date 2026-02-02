"""
Planter UNSW-NB15 BMv2 Integration
==================================

In-network ML classification for network intrusion detection
using the Planter methodology on BMv2 software switches.

Components:
- prepare_data: Prepare UNSW-NB15 dataset for Planter
- train_model: Train Decision Tree and generate P4 code
- demo: Quick demonstration script
"""

__version__ = "0.1.0"
__author__ = "Pedro Suffert"

from .config import Config

__all__ = ["Config", "__version__"]
