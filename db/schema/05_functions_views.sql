/*
Функции и представления
*/

set search_path to kuzmin_food, exts;


-- Статистика по ресторанам.

create or replace function get_statistic()
returns table (
    restaurant_name varchar(50),
    best_product_name varchar(50),
    total_amount numeric(12,2),
    avg_amount numeric(12,2),
    best_user varchar(50)
)
language sql
stable
as $$
    with delivered_orders as (
        select order_id, restaurant_id, client_id, total_amount
        from kuzmin_food."order"
        where status = 'доставлен'
    ),
    restaurant_totals as (
        select restaurant_id,
               sum(total_amount) as total_amount,
               avg(total_amount) as avg_amount
        from delivered_orders
        group by restaurant_id
    ),
    product_sales as (
        select o.restaurant_id,
               p.product_id,
               p.product_name,
               sum(os.quantity) as sold
        from delivered_orders o
        join kuzmin_food.order_structure os on os.order_id = o.order_id
        join kuzmin_food.product p on p.product_id = os.product_id
        group by o.restaurant_id, p.product_id, p.product_name
    ),
    best_products as (
        select distinct on (restaurant_id)
               restaurant_id,
               product_name
        from product_sales
        order by restaurant_id, sold desc, random()
    ),
    client_orders as (
        select o.restaurant_id,
               c.login,
               count(*) as order_count
        from delivered_orders o
        join kuzmin_food.client c on c.client_id = o.client_id
        group by o.restaurant_id, c.login
    ),
    best_clients as (
        select distinct on (restaurant_id)
               restaurant_id,
               login
        from client_orders
        order by restaurant_id, order_count desc, random()
    )
    select r.restaurant_name,
           bp.product_name,
           coalesce(rt.total_amount, 0)::numeric(12,2),
           coalesce(rt.avg_amount, 0)::numeric(12,2),
           bc.login
    from kuzmin_food.restaurant r
    left join restaurant_totals rt on rt.restaurant_id = r.restaurant_id
    left join best_products bp on bp.restaurant_id = r.restaurant_id
    left join best_clients bc on bc.restaurant_id = r.restaurant_id
    order by r.restaurant_name;
$$;
