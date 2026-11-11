/*
Триггеры целостности
*/

set search_path to kuzmin_food, exts;


-- BR-7.3: все блюда в заказе — из ресторана заказа

create or replace function check_order_structure_restaurant() returns trigger
language plpgsql as $$
declare
    v_order_restaurant uuid;
    v_product_restaurant uuid;
begin
    select restaurant_id into v_order_restaurant
    from "order"
    where order_id = new.order_id;

    select restaurant_id into v_product_restaurant
    from product
    where product_id = new.product_id;

    if v_order_restaurant <> v_product_restaurant then
        raise exception 'блюдо % из ресторана %, а заказ % из ресторана %',
            new.product_id, v_product_restaurant,
            new.order_id, v_order_restaurant
            using errcode = 'check_violation';
    end if;

    return new;
end $$;

drop trigger if exists trg_order_structure_restaurant on order_structure;

create trigger trg_order_structure_restaurant
    before insert or update on order_structure
    for each row
    execute function check_order_structure_restaurant();


-- BR-7.3: ресторан заказа нельзя сменить, если в заказе уже есть позиции

create or replace function lock_order_restaurant() returns trigger
language plpgsql as $$
begin
    if new.restaurant_id <> old.restaurant_id
       and exists (select 1 from order_structure where order_id = new.order_id) then
        raise exception 'нельзя сменить ресторан заказа %: в заказе уже есть позиции',
            new.order_id
            using errcode = 'check_violation';
    end if;

    return new;
end $$;

drop trigger if exists trg_order_restaurant_locked on "order";

create trigger trg_order_restaurant_locked
    before update of restaurant_id on "order"
    for each row
    execute function lock_order_restaurant();


-- BR-9.1: отзыв ссылается на существующий объект нужного типа

create or replace function check_review_entity() returns trigger
language plpgsql as $$
begin
    if new.entity_type = 'блюдо' then
        if not exists (select 1 from product where product_id = new.entity_id) then
            raise exception 'блюдо % не найдено, отзыв оставить не на что',
                new.entity_id
                using errcode = 'check_violation';
        end if;
    elsif new.entity_type = 'ресторан' then
        if not exists (select 1 from restaurant where restaurant_id = new.entity_id) then
            raise exception 'ресторан % не найден, отзыв оставить не на что',
                new.entity_id
                using errcode = 'check_violation';
        end if;
    elsif new.entity_type = 'заказ' then
        if new.entity_id <> new.order_id then
            raise exception 'отзыв на заказ % не может ссылаться на заказ %',
                new.order_id, new.entity_id
                using errcode = 'check_violation';
        end if;
    end if;

    return new;
end $$;

drop trigger if exists trg_review_entity on review;

create trigger trg_review_entity
    before insert or update on review
    for each row
    execute function check_review_entity();


-- BR-9.6, BR-9.7: рейтинг блюда и ресторана — среднее по отзывам

create or replace function recalc_rating(
    p_entity_type review_entity_type,
    p_entity_id uuid
) returns void
language plpgsql as $$
begin
    if p_entity_type = 'блюдо' then
        update product
        set rating = (
            select avg(r.rating)
            from review r
            where r.entity_type = 'блюдо'
              and r.entity_id = p_entity_id
        )
        where product_id = p_entity_id;
    elsif p_entity_type = 'ресторан' then
        update restaurant
        set rating = (
            select avg(r.rating)
            from review r
            where r.entity_type = 'ресторан'
              and r.entity_id = p_entity_id
        )
        where restaurant_id = p_entity_id;
    end if;
end $$;

create or replace function rating_change() returns trigger
language plpgsql as $$
begin
    if tg_op = 'DELETE' then
        perform recalc_rating(old.entity_type, old.entity_id);
        return old;
    end if;

    if tg_op = 'UPDATE'
       and (old.entity_type is distinct from new.entity_type
            or old.entity_id is distinct from new.entity_id) then
        perform recalc_rating(old.entity_type, old.entity_id);
    end if;

    perform recalc_rating(new.entity_type, new.entity_id);
    return new;
end $$;

drop trigger if exists trg_rating_change on review;

create trigger trg_rating_change
    after insert or update or delete on review
    for each row
    execute function rating_change();
