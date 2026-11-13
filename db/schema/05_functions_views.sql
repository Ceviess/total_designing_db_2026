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


-- Отчёт сколько денег по месяцам.

create or replace view how_much_money as
with recursive months as (
    select date_trunc('month', min(order_timestamp)) as month_start
    from kuzmin_food."order"
    where status = 'доставлен'
    having count(*) > 0

    union all

    select m.month_start + interval '1 month'
    from months m
    where m.month_start + interval '1 month' <= (
        select date_trunc('month', max(order_timestamp))
        from kuzmin_food."order"
        where status = 'доставлен'
    )
),

order_totals as (
    select date_trunc('month', order_timestamp) as month_start,
           sum(order_amount) as sum_no_commission,
           sum(total_amount) as sum_with_commission
    from kuzmin_food."order"
    where status = 'доставлен'
    group by date_trunc('month', order_timestamp)
),
pay_totals as (
    select make_date(year, month, 1) as month_start,
           sum(amount) as courier_pay
    from kuzmin_food.courier_pay
    group by make_date(year, month, 1)
),
month_report as (
    select m.month_start,
           coalesce(ot.sum_no_commission, 0)::numeric(12,2)
               as sum_no_commission,
           coalesce(ot.sum_with_commission, 0)::numeric(12,2)
               as sum_with_commission,
           coalesce(ot.sum_with_commission, 0)::numeric(12,2)
               - coalesce(ot.sum_no_commission, 0)::numeric(12,2)
               as commission,
           coalesce(pt.courier_pay, 0)::numeric(12,2)
               as courier_pay
    from months m
    left join order_totals ot on ot.month_start = m.month_start
    left join pay_totals pt on pt.month_start = m.month_start
),
with_prev as (
    select month_start,
           sum_no_commission,
           sum_with_commission,
           commission,
           lag(commission) over (order by month_start) as prev_commission,
           courier_pay
    from month_report
)
select to_char(month_start, 'YYYY-MM') as year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission - prev_commission as commission_diff,
       courier_pay,
       commission - courier_pay as net_profit
from with_prev;
