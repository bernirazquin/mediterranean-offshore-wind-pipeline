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

'''
Tiles download bounding Mediterranean, using ETOPO2022 15s resolution dataset from NOAA NGDC 
via OpenDAP avoiding the need to download the entire global dataset. 

The get_depth function iterates through the tiles, trying to find the depth at the specified latitude and 
longitude by selecting the nearest point in the dataset. 
 
If a tile does not contain the requested location, it continues to the next tile until it finds a match or exhausts all options
'''

TILES = [
    "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N30W015_surface.nc",
    "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N30E000_surface.nc",
    "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N30E015_surface.nc",
    "https://www.ngdc.noaa.gov/thredds/dodsC/global/ETOPO2022/15s/15s_surface_elev_netcdf/ETOPO_2022_v1_15s_N30E030_surface.nc",
]


def get_depth(lat, lon):
    for url in TILES:
        try:
            ds = xr.open_dataset(url)
            depth = float(ds["z"].sel(lat=lat, lon=lon, method="nearest").values)
            ds.close()
            return depth
        except:
            continue
    raise ValueError(f"No tile found for ({lat}, {lon})")

def main ():
    print ("Connecting to ETOPO 2022 via OpeNDAP...")
    rows = []
    for site, (lat, lon) in SITES.items():
        depth = get_depth(lat, lon)
        rows.append({
            "location_name":   site,
            "latitude":        lat,
            "longitude":       lon,
            "depth_m":         depth,
            "depth_category":  (
                "shallow"      if depth > -50  else
                "transitional" if depth > -200 else
                "deep"
            ),
            "viable_fixed":    depth >= -50,
            "viable_floating": depth >= -200,
        })
        print (f"Retrieved depth for {site}: {depth:0.f} m")

df = pd.DataFrame(rows)
print ("\n Results:")
print (df[["location_name", "latitude", "longitude", "depth_m", "depth_category"]])

