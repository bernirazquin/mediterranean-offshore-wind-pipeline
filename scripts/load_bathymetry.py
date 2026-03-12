import xarray as xr
import pandas as pd
from google.cloud import bigquery
import json, os

SITES = {
    "ALBORAN_SEA":        (36.0, -4.0),
    "GULF_OF_VALENCIA":   (39.5, -0.1),
    "EBRO_DELTA":         (40.7,  0.9),
    "COSTA_BRAVA":        (42.1,  3.3),
    "GULF_OF_LYON":       (43.0,  4.0),
    "BALEARIC_SEA":       (39.0,  2.5),
    "TYRRHENIAN_SEA":     (40.0, 12.0),
    "STRAIT_OF_SICILY":   (37.0, 11.5),
    "NORTH_ADRIATIC_SEA": (44.5, 13.0),
    "IONIAN_SEA":         (38.0, 18.0),
    "AEGEAN_SEA":         (37.5, 25.0),
    "LIBYAN_COAST":       (33.0, 20.0),
    "LEVANTINE_SEA":      (34.0, 30.0),
    "CYPRUS_COAST":       (35.0, 34.0),
}

