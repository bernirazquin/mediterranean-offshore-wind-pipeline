{% macro generate_grid_id(lat, lon) %}
    {# 
        MACRO: generate_grid_id
        PURPOSE: Standardizes raw coordinates into a universal 0.25° spatial hash key.
        
        HOW IT WORKS:
        1. The Math:  `floor(coord / 0.25) * 0.25 + 0.125` snaps any high-resolution 
                      coordinate to the exact center of a 0.25-degree grid cell.
        2. The Round: `round(..., 4)` strips away microscopic floating-point noise 
                      (e.g., turning 42.1250000001 into exactly 42.125).
        3. The Cast:  `cast(... as string)` forces the hashing function to read the 
                      literal text "42.125". If we hash raw floats, BigQuery can 
                      generate different hashes for identically looking numbers, 
                      causing silent join failures between datasets.
                      
        USAGE: Used across all staging models (Wind, Wave, Bathymetry, Coastline) 
               to ensure perfectly matching `spatial_id` surrogate keys.
    #}
    
    {{ dbt_utils.generate_surrogate_key([
        'cast(round(floor(' ~ lat ~ ' / 0.25) * 0.25 + 0.125, 4) as string)',
        'cast(round(floor(' ~ lon ~ ' / 0.25) * 0.25 + 0.125, 4) as string)'
    ]) }}
{% endmacro %}