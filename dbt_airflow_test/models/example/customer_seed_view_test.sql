{{ config(materialized='view') }}

-- cte in view 
with customer_info as (

    select *
    from {{ ref('customer_seed_view') }}

)

select * from customer_info