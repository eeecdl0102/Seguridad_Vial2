{% macro pick_column(relation, candidates, required=true) %}
    {%- if execute -%}
        {#- mapa NOMBRE_EN_MAYUSCULA -> nombre real en la tabla -#}
        {%- set lookup = {} -%}
        {%- for c in adapter.get_columns_in_relation(relation) -%}
            {%- do lookup.update({c.name | upper: c.name}) -%}
        {%- endfor -%}

        {%- set found = [] -%}
        {%- for cand in candidates -%}
            {%- if (cand | upper) in lookup and found | length == 0 -%}
                {%- do found.append(lookup[cand | upper]) -%}
            {%- endif -%}
        {%- endfor -%}

        {%- if found | length > 0 -%}
            {{ adapter.quote(found[0]) }}
        {%- elif required -%}
            {{ exceptions.raise_compiler_error(
                "Ninguna de las columnas " ~ candidates ~ " existe en " ~ relation) }}
        {%- else -%}
            NULL
        {%- endif -%}
    {%- else -%}
        NULL
    {%- endif -%}
{% endmacro %}