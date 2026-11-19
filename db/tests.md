# Протокол для самопроверки

Заполняется по желанию. 

По данному протоколу работа будет проверяться преподавателем.

**Если на каком-то этапе функционал оказывается нерабочим, значит учащийся проигнорировал обязательное тестирование и работа может быть отправлена на доработку без проверки и комментариев или по работе может быть проставлен незачет, если лимит доработок исчерпан.**

## Окружение

| Параметр | Значение |
|---|---|
| PostgreSQL version | `PostgreSQL 17.9 on x86_64-pc-linux-gnu, compiled by gcc (Ubuntu 7.5.0-3ubuntu1~18.04) 7.5.0, 64-bit` |
| pg_dump version | `17.12` |
| Дата проверки | 2026-11-14 |
| Схема | `kuzmin_food` |
| Роль-аудитор | `inspector` |

Все проверки — под `inspector`, если не указано иное.

Заполняй «Факт» и «Вердикт» по каждой проверке. «Вердикт»: `OK` / `FAIL: <что именно>`.

---

## A. Подготовка

### A.1. Восстановление бэкапа

Ожидается: без ошибок.  
Факт: `pg_restore` завершился с кодом 0, сообщений об ошибках нет. В пустую базу `foodexpress_restore`, где заранее созданы схема `exts` и расширение `uuid-ossp`, восстановлены все 75 объектов архива. Дамп снят `pg_dump` 17.12 с сервера 17.9 — мажорная версия одна.  
Вердикт: OK

### A.2. Переключение на inspector

```sql
SET ROLE inspector;
SET search_path TO kuzmin_food, exts;
SELECT current_user;
```

Ожидается: `inspector`.  
Факт: Подключение выполнено отдельной учётной записью `inspector`; `current_user` и `session_user` — `inspector`.  
Вердикт: OK

---

## B. FOOD-101: Структура схемы

### B.1. Схема существует

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_food';
```

Ожидается: `kuzmin_food`.  
Факт: `kuzmin_food`.  
Вердикт: OK

### B.2. Схема `exts` с `uuid-ossp`

```sql
SELECT extname, extnamespace::regnamespace AS schema
FROM pg_extension WHERE extname = 'uuid-ossp';
```

Ожидается: `uuid-ossp`, схема `exts`.  
Факт: `uuid-ossp`, схема `exts`.  
Вердикт: OK

### B.3. Все 12 исходных таблиц + N после нормализации

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'kuzmin_food'
ORDER BY table_name;
```

Ожидается: `address`, `client`, `client_address`, `courier`, `courier_pay`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review` (12 + N штук).  
Факт: 13 строк: 12 таблиц (`address`, `client`, `client_address`, `courier`, `courier_pay`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review`) и представление `how_much_money`.  
Вердикт: OK

### B.4. Все PK — `uuid`

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'kuzmin_food'
  AND column_name LIKE '%_id'
  AND data_type != 'uuid';
```

Ожидается: пусто.  
Факт: Пусто: все первичные и внешние ключи имеют тип `uuid`.  
Вердикт: OK

### B.5. Enum-типы

```sql
SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'kuzmin_food'
GROUP BY t.typname
ORDER BY t.typname;
```

Ожидается: 8 типов со значениями из constraints.md.  
Факт: 8 типов: `restaurant_status` (`активен`, `неактивен`), `product_status` (`доступно`, `нет_в_наличии`, `архив`), `courier_status` (`свободен`, `занят`, `на_доставке`, `уволен`), `order_status` (`создан`, `готовится`, `в_доставке`, `доставлен`, `отменён`), `order_pay_status` (`ожидает`, `оплачен`, `ошибка`), `payment_status` (`успех`, `ошибка`, `в_обработке`), `payment_type` (`карта`, `наличные`, `безнал`), `review_entity_type` (`блюдо`, `ресторан`, `заказ`).  
Вердикт: OK

### B.6. FK-ограничения

```sql
SELECT conname, conrelid::regclass AS tbl, confrelid::regclass AS ref
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'kuzmin_food'::regnamespace
ORDER BY tbl, conname;
```

Ожидается: не менее 15 FK, все из erd.md.  
Факт: 16 внешних ключей: 5 у `order`, по 2 у `client_address`, `order_structure`, `product`, `review`, по 1 у `restaurant`, `payment`, `courier_pay`.  
Вердикт: OK

### B.7. Пароль — MD5

```sql
SELECT length(password) AS len, password
FROM client LIMIT 5;
```

Ожидается: `len = 32`, hex-строка.  
Факт: в выборке 5 строк, у всех длина пароля 32; дополнительно проверена вся таблица — 10 строк, все значения — hex-строки из символов `0-9a-f`.  
Вердикт: OK

---

## C. FOOD-102: `insert_test_data(value)`

### C.1. Чистая схема

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.  
Факт: Без ошибок; все 12 таблиц очищены.  
Вердикт: OK

### C.2. Первый запуск

```sql
CALL insert_test_data(10);
```

Ожидается: без ошибок.  
Факт: Без ошибок; сгенерирован набор из 10 клиентов.  
Вердикт: OK

### C.3. Распределение строк (BR-11.7)

```sql
SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
ORDER BY tbl;
```

Ожидается: 10, 10, 10, 10, 50, 50, 50, 50, 50.  
Факт: 10, 10, 10, 10, 50, 50, 50, 50, 50 — совпадает с BR-11.7.  
Вердикт: OK

### C.4. Адреса ресторанов vs клиентов (BR-11.7)

```sql
SELECT 'restaurant addresses' AS cat, count(*) FROM restaurant WHERE address_id IS NOT NULL
UNION ALL
SELECT 'total addresses', count(*) FROM address;
```

Ожидается: 10 ресторанных адресов, 50 всего → 40 клиентских.  
Факт: 10 адресов у ресторанов, 50 всего, 40 клиентских; в `client_address` 40 связей.  
Вердикт: OK

### C.5. Нет пустых строк (BR-11.3)

```sql
SELECT count(*) FROM client WHERE login = '' OR password = '' OR phone_number = '';
-- и аналогично для других varchar-полей с NOT NULL
```

Ожидается: 0.  
Факт: 0 пустых строк во всех обязательных `varchar` и `text` столбцах; запрос из блока расширен на остальные таблицы по той же схеме.  
Вердикт: OK

### C.6. Нет NULL там, где запрещено (BR-11.3)

```sql
SELECT count(*) FROM "order" WHERE client_id IS NULL OR restaurant_id IS NULL
  OR courier_id IS NULL OR address_id IS NULL OR total_amount IS NULL;
-- и аналогично для других NOT NULL полей
```

Ожидается: 0.  
Факт: 0 `NULL` во всех `NOT NULL` столбцах; запрос из блока расширен на остальные таблицы по той же схеме.  
Вердикт: OK

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(*) FROM courier WHERE status != 'уволен';
```

Ожидается: `>= 1`.  
Факт: 8 работающих курьеров; 2 из 10 уволены.  
Вердикт: OK

### C.8. `courier_pay` консистентен с правилами (BR-10.2)

```sql
SELECT cp.year, cp.month, cp.courier_id, cp.amount, cp.coefficient_used,
       round(coalesce((
           SELECT sum(o.commission)
           FROM "order" o
           WHERE o.courier_id = cp.courier_id
             AND o.status = 'доставлен'
             AND extract(year  from o.order_timestamp) = cp.year
             AND extract(month from o.order_timestamp) = cp.month
       ), 0) * cp.coefficient_used, 2) AS expected_amount
FROM courier_pay cp
LIMIT 20;
```

Ожидается: `amount = expected_amount` в каждой строке.  
Факт: в выборке 20 строк расхождений нет; дополнительно проверены все 60 строк (10 курьеров × 6 месяцев) — расхождений 0, суммы неотрицательны и равны «коэффициент × комиссия доставленных заказов месяца». Точные суммы зависят от случайных цен и при каждом прогоне другие.  
Вердикт: OK

### C.9. Повторный вызов не ломает

```sql
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        CALL insert_test_data(10);
    END LOOP;
END $$;
```

Ожидается: без ошибок, данные добавляются или заменяются (по решению студента, задокументированному в constraints.md).    
Факт: 10 повторных вызовов подряд прошли без ошибок. Каждый вызов добавляет новый набор из 10 строк, а не заменяет прошлый: очистки в генераторе нет, для неё есть отдельная процедура `erase_test_data()`. Уникальность логинов, телефонов, адресов и названий при этом сохраняется. После блока выполнено `CALL erase_test_data(); CALL insert_test_data(10);`, чтобы блоки D–I работали с одним набором.  
Вердикт: OK

---

## D. Проверки бизнес-правил на сгенерированных данных

### D.1. Все FK валидны (нет orphans)

```sql
SELECT 'order_structure → order' AS fk, count(*) AS orphans
FROM order_structure os
LEFT JOIN "order" o ON os.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'order_structure → product', count(*)
FROM order_structure os
LEFT JOIN product p ON os.product_id = p.product_id
WHERE p.product_id IS NULL
UNION ALL
SELECT 'payment → order', count(*)
FROM payment pmt
LEFT JOIN "order" o ON pmt.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'review → order', count(*)
FROM review r
LEFT JOIN "order" o ON r.order_id = o.order_id
WHERE o.order_id IS NULL
UNION ALL
SELECT 'courier_pay → courier', count(*)
FROM courier_pay cp
LEFT JOIN courier c ON cp.courier_id = c.courier_id
WHERE c.courier_id IS NULL
UNION ALL
SELECT 'client_address → client', count(*)
FROM client_address ca
LEFT JOIN client c ON ca.client_id = c.client_id
WHERE c.client_id IS NULL
UNION ALL
SELECT 'client_address → address', count(*)
FROM client_address ca
LEFT JOIN address a ON ca.address_id = a.address_id
WHERE a.address_id IS NULL;
```

Ожидается: все 0.  
Факт: Все 7 проверок вернули 0 orphan-строк.  
Вердикт: OK

### D.2. Минимальная сумма заказа (BR-1.8)

```sql
SELECT count(*) FROM "order" WHERE total_amount < 1000;
```

Ожидается: 0.  
Факт: 0.  
Вердикт: OK

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(*) FROM "order" WHERE round(order_amount * 0.10, 2) != commission;
```

Ожидается: 0.  
Факт: 0.  
Вердикт: OK

### D.4. `total_amount = order_amount + commission`

```sql
SELECT count(*) FROM "order"
WHERE round(order_amount + commission, 2) != total_amount;
```

Ожидается: 0.  
Факт: 0.  
Вердикт: OK

### D.5. Дата доставки не раньше создания (BR-7.13)

```sql
SELECT count(*) FROM "order"
WHERE delivery_timestamp IS NOT NULL AND delivery_timestamp < order_timestamp;
```

Ожидается: 0.  
Факт: 0.  
Вердикт: OK

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) FROM "order" o
LEFT JOIN client_address ca
  ON ca.client_id = o.client_id AND ca.address_id = o.address_id
WHERE ca.client_id IS NULL;
```

Ожидается: 0.    
Факт: 0.  
Вердикт: OK

### D.7. Все блюда в заказе из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id)
FROM order_structure os
JOIN "order" o ON os.order_id = o.order_id
JOIN product p ON os.product_id = p.product_id
WHERE p.restaurant_id != o.restaurant_id;
```

Ожидается: 0.  
Факт: 0.  
Вердикт: OK

### D.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT order_id, count(*) AS cnt
FROM payment
WHERE status = 'успех'
GROUP BY order_id
HAVING count(*) != 1;
```

Ожидается: пусто.  
Факт: Пусто: заказов с двумя успешными попытками нет. Запрос видит только заказы, у которых успешная попытка есть, поэтому заказы без неё в результат не попадают. У всех 40 доставленных заказов успешная попытка ровно одна; у 8 заказов в работе попытка в обработке (`pay_status = 'ожидает'`), у 2 отменённых — с ошибкой (`pay_status = 'ошибка'`). Так выполнено BR-8.7: `pay_status` выводится из статуса попытки.  
Вердикт: OK

### D.9. Сумма оплаты = `total_amount` заказа (BR-8.4)

```sql
SELECT count(*) FROM payment p
JOIN "order" o ON p.order_id = o.order_id
WHERE p.amount != o.total_amount;
```

Ожидается: 0.  
Факт: 0.  
Вердикт: OK

### D.10. Нет дубликатов в `client_address` (BR-2.5)

```sql
SELECT client_id, address_id, count(*)
FROM client_address
GROUP BY client_id, address_id
HAVING count(*) > 1;
```

Ожидается: пусто.  
Факт: Пусто.  
Вердикт: OK

### D.11. Нет дубликатов в `order_structure` (BR-7.16)

```sql
SELECT order_id, product_id, count(*)
FROM order_structure
GROUP BY order_id, product_id
HAVING count(*) > 1;
```

Ожидается: пусто.  
Факт: Пусто.  
Вердикт: OK

### D.12. `work_end > work_start` (BR-4.4)

```sql
SELECT count(*) FROM restaurant WHERE work_end <= work_start;
```

Ожидается: 0.  
Факт: 0.  
Вердикт: OK

### D.13. `dismissal_date >= hire_date` (BR-6.3)

```sql
SELECT count(*) FROM courier
WHERE dismissal_date IS NOT NULL AND dismissal_date < hire_date;
```

Ожидается: 0.  
Факт: 0.  
Вердикт: OK

### D.14. Рейтинг блюд/ресторанов соответствует отзывам (BR-9.6)

```sql
-- product.rating = AVG(review.rating) по отзывам на блюдо
SELECT p.product_id, p.rating,
       (SELECT round(avg(r.rating), 2) FROM review r
        WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id) AS expected
FROM product p
WHERE p.rating IS NOT NULL
LIMIT 20;
```

Ожидается: `rating = expected`.  
Факт: запрос вернул 8 блюд с заполненным рейтингом; у всех рейтинг равен `round(avg(review.rating), 2)`. Дополнительно тем же условием проверены все 10 ресторанов: у 8 заполненный рейтинг совпадает со средним, у 2 отзывов нет и рейтинг `NULL`.  
Вердикт: OK

---

## E. Функции и процедуры

### E.1. `add_product` — успешный вызов

Аргументы `CALL` не принимают подзапросы (`cannot use subquery in CALL argument`), поэтому идентификаторы сначала читаются в переменные PL/pgSQL, а затем передаются в процедуру:

```sql
SELECT count(*) AS before FROM product;

DO $$
DECLARE
    v_restaurant uuid;
    v_category   uuid;
BEGIN
    SELECT restaurant_id INTO v_restaurant FROM restaurant LIMIT 1;
    SELECT product_category_id INTO v_category FROM product_category LIMIT 1;

    CALL add_product(
        p_restaurant_id       => v_restaurant,
        p_product_category_id => v_category,
        p_name                => 'Тестовое блюдо',
        p_price               => 250,
        p_rating              => 4.5,
        p_status              => 'доступно',
        p_description         => 'Описание'
    );
END $$;

SELECT count(*) AS after FROM product;
```

Ожидается: `after = before + 1`.  
Факт: `before = 50`, `after = 51` — блюдо добавлено; вызов выполнен под `inspector`.  
Вердикт: OK

### E.2. `add_product` — падает на несуществующий ресторан

```sql
DO $$
DECLARE
    v_category uuid;
BEGIN
    SELECT product_category_id INTO v_category FROM product_category LIMIT 1;

    CALL add_product(
        p_restaurant_id       => '00000000-0000-0000-0000-000000000000',
        p_product_category_id => v_category,
        p_name                => 'Тестовое блюдо 2',
        p_price               => 250,
        p_rating              => 4.5,
        p_status              => 'доступно',
        p_description         => 'Описание'
    );
END $$;
```

Ожидается: ошибка ограничения внешнего ключа.  
Факт: Ошибка `23503` от ограничения `fk_product_restaurant`: `insert or update on table "product" violates foreign key constraint "fk_product_restaurant"`. Сообщение формирует сама схема, процедура его не перехватывает; пользователю текст показывает бэкенд.  
Вердикт: OK

### E.3. `rating_change` — пересчитывает рейтинг

```sql
-- Блюдо, заказ и клиент, у которых ещё нет отзыва на это блюдо
DROP TABLE IF EXISTS review_probe;

CREATE TEMP TABLE review_probe AS
SELECT p.product_id, p.rating AS rating_before, o.order_id, o.client_id
FROM product p
JOIN order_structure os ON os.product_id = p.product_id
JOIN "order" o ON o.order_id = os.order_id
WHERE p.rating IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM review r
      WHERE r.order_id = o.order_id
        AND r.entity_type = 'блюдо'
        AND r.entity_id = p.product_id
  )
ORDER BY p.product_id
LIMIT 1;

SELECT product_id, rating_before FROM review_probe;

INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type,
                    order_id, description, rating)
SELECT exts.uuid_generate_v4(), client_id, localtimestamp, product_id,
       'блюдо', order_id, 'Тестовый отзыв', 5
FROM review_probe;

SELECT p.product_id, p.rating AS rating_after
FROM product p
JOIN review_probe rp ON rp.product_id = p.product_id;
```

Пара «заказ — блюдо» выбирается заранее и без отзыва, иначе вставка упрётся в `unique_review_entity`.

Ожидается: `rating_after` пересчитан по всем отзывам блюда, то есть `rating_after = (rating_before * n + 5) / (n + 1)`, где `n` — число прежних отзывов; у блюда с единственным отзывом это `(rating_before + 5) / 2`.  
Факт: Рейтинг блюда до вставки 4.00, после вставки отзыва с оценкой 5 — 4.50; триггер пересчитал среднее.  
Вердикт: OK

### E.4. `rating_change` — удаление отзыва

```sql
DROP TABLE IF EXISTS deleted_review;

CREATE TEMP TABLE deleted_review AS
SELECT entity_id
FROM review
WHERE description = 'Тестовый отзыв';

DELETE FROM review WHERE description = 'Тестовый отзыв';

SELECT p.product_id, p.rating AS rating_after_delete
FROM product p
JOIN deleted_review d ON d.entity_id = p.product_id;
```

Блок выполняется после E.3: удаляется вставленный там отзыв, а блюдо запоминается до удаления, чтобы прочитать рейтинг уже после пересчёта.

Ожидается: если других отзывов нет — `rating IS NULL`; иначе — пересчитан. В нашем прогоне у блюда был один отзыв, поэтому `rating_after_delete` вернулся к `rating_before`.  
Факт: После удаления тестового отзыва рейтинг вернулся к 4.00 — пересчёт по оставшимся отзывам.  
Вердикт: OK

### E.5. `get_statistic()`

```sql
SELECT * FROM get_statistic();
```

Ожидается:
- Колонки: `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`.
- По одной строке на ресторан.
- `best_user` = `client.login` (не NULL при наличии заказов).

Факт: 10 строк — по одной на каждый из 10 ресторанов, названия не повторяются. Колонки и их порядок совпадают с контрактом. У ресторанов без доставленных заказов `total_amount = 0.00`, `avg_amount = 0.00`, `best_product_name = NULL`, `best_user = NULL`. У остальных ресторанов `best_product_name` заполнен, `best_user` — логин клиента (кириллическая строка). На специально подготовленном равенстве возвращается один из лидеров.
Вердикт: OK

### E.6. `courier_salary()`

```sql
-- До
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;

CALL courier_salary();

-- После
SELECT courier_id, coefficient FROM courier ORDER BY courier_id;
SELECT year, month, courier_id, amount, coefficient_used
FROM courier_pay
ORDER BY year DESC, month DESC, courier_id
LIMIT 20;
```

Ожидается:
- `courier.coefficient` пересчитан для работающих (по BR-10.2).
- У уволенных — не изменился.
- `courier_pay` содержит запись за текущий месяц.

Факт: до вызова 8 работающих и 2 уволенных курьера имели коэффициент 0.10. После вызова у всех те же 0.10: у работающих пересчёт по BR-10.2 дал 0.1, потому что в текущем месяце 4 доставленных заказа, по одному на четырёх курьеров, а следующий порог начинается со 151 доставки; у уволенных коэффициент не менялся. Записей `courier_pay` за текущий месяц до и после вызова по 10 — по одной на курьера, суммы неотрицательны и равны «0.10 × комиссия доставленных заказов месяца» (точные суммы зависят от случайных цен), `coefficient_used = 0.10`. При тестовых объёмах коэффициент не меняется: доставок на курьера слишком мало, чтобы дойти до порога 151.    
Вердикт: OK

### E.7. `courier_salary()` — повторный вызов

```sql
CALL courier_salary();
SELECT count(*) FROM courier_pay
WHERE year = extract(year from current_date)
  AND month = extract(month from current_date);
```

Ожидается: количество не изменилось (idempotency / обновление).    
Факт: повторный вызов оставил те же 10 записей за текущий месяц, дублей нет; суммы и `coefficient_used` не изменились. Дополнительно в транзакции на 151 доставленном заказе одного курьера первый вызов поставил коэффициент 0.20, второй оставил одну запись за месяц без дубля; после отката изменения не сохранились.  
Вердикт: OK

---

## F. Представление `how_much_money`

### F.1. Колонки

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'kuzmin_food'
  AND table_name = 'how_much_money'
ORDER BY ordinal_position;
```

Ожидается: `year_month` (text), `sum_no_commission`, `sum_with_commission`, `commission`, `prev_commission`, `commission_diff`, `courier_pay`, `net_profit` (numeric).  
Факт: 8 колонок в нужном порядке: `year_month` (`text`), остальные семь — `numeric`.  
Вердикт: OK

### F.2. Месяцы покрыты

```sql
SELECT * FROM how_much_money ORDER BY year_month;
```

Ожидается: месяцы от первого доставленного заказа до последнего (не пропущено ни одного).  
Факт: 6 строк: `2026-06`, `2026-07`, `2026-08`, `2026-09`, `2026-10`, `2026-11`. Первый доставленный заказ — 2026-06, последний — 2026-11; все месяцы между ними присутствуют.  
Вердикт: OK

### F.3. Месяцы без заказов присутствуют (BR-11.9)

```sql
SELECT year_month FROM how_much_money
WHERE sum_no_commission = 0 OR sum_no_commission IS NULL;
```

Ожидается: если в какие-то месяцы заказов не было — они есть в результате.    
Факт: на данных `insert_test_data(10)` доставленные заказы есть во всех шести месяцах, поэтому запрос вернул 0 строк. Отдельно проверено в транзакции: после добавления доставленного заказа в 2027-02 отчёт содержал 9 строк, и в нём появились пустые месяцы `2026-12` (суммы, комиссия, выплаты и прибыль — 0.00, `prev_commission = 470.20`, `commission_diff = -470.20`) и `2027-01` (все суммы 0.00, `prev_commission = 0.00`, `commission_diff = 0.00`). После отката данные вернулись.   
Вердикт: OK

### F.4. Корректность сумм

```sql
SELECT year_month,
       sum_no_commission,
       sum_with_commission,
       commission,
       prev_commission,
       commission_diff,
       courier_pay,
       net_profit
FROM how_much_money
ORDER BY year_month
LIMIT 10;
```

Ожидается:
- `commission = sum_with_commission - sum_no_commission`.
- `commission_diff = commission - prev_commission` (NULL для первого месяца).
- `net_profit = commission - courier_pay`.

Факт:

| year_month | sum_no_commission | sum_with_commission | commission | prev_commission | commission_diff | courier_pay | net_profit |
|---|---|---|---|---|---|---|---|
| 2026-06 | 4616.00 | 5077.60 | 461.60 | NULL | NULL | 46.16 | 415.44 |
| 2026-07 | 8857.00 | 9742.70 | 885.70 | 461.60 | 424.10 | 88.57 | 797.13 |
| 2026-08 | 11659.00 | 12824.90 | 1165.90 | 885.70 | 280.20 | 116.59 | 1049.31 |
| 2026-09 | 8388.00 | 9226.80 | 838.80 | 1165.90 | -327.10 | 83.88 | 754.92 |
| 2026-10 | 12592.00 | 13851.20 | 1259.20 | 838.80 | 420.40 | 125.92 | 1133.28 |
| 2026-11 | 4702.00 | 5172.20 | 470.20 | 1259.20 | -789.00 | 47.02 | 423.18 |

Во всех строках `commission = sum_with_commission - sum_no_commission`, `commission_diff = commission - prev_commission` (у первого месяца `NULL`), `net_profit = commission - courier_pay`.  
Вердикт: OK

---

## G. Права `inspector`

### G.1. Права на схему

```sql
SELECT
    nspname AS schema_name,
    has_schema_privilege('inspector', nspname, 'USAGE')  AS usage,
    has_schema_privilege('inspector', nspname, 'CREATE') AS create
FROM pg_namespace
WHERE nspname = 'kuzmin_food';
```

Ожидается: `kuzmin_food`, `true`, `true` (полный доступ).  
Факт: `kuzmin_food`, `usage = true`, `create = true`. Скрипт прав применён повторно — без ошибок.  
Вердикт: OK

### G.2. Права на таблицы

```sql
SELECT table_name, string_agg(privilege_type, ', ') AS privs
FROM information_schema.role_table_grants
WHERE grantee = 'inspector' AND table_schema = 'kuzmin_food'
GROUP BY table_name;
```

Ожидается: у каждой таблицы `SELECT, INSERT, UPDATE, DELETE` (или `ALL`).  
Факт: 13 строк — 12 таблиц и представление `how_much_money`; у каждой `DELETE, INSERT, SELECT, UPDATE`.  
Вердикт: OK

### G.3. `information_schema` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'kuzmin_food';
RESET ROLE;
```

Ожидается: 12 + N (количество таблиц).  
Факт: 13 — 12 таблиц и представление `how_much_money`.  
Вердикт: OK

### G.4. `pg_catalog` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM pg_catalog.pg_tables
WHERE schemaname = 'kuzmin_food';
RESET ROLE;
```

Ожидается: 12 + N.  
Факт: 12.  
Вердикт: OK

### G.5. Все процедуры/функции работают под `inspector`

```sql
SET ROLE inspector;
SET search_path TO kuzmin_food, exts;

CALL erase_test_data();
CALL insert_test_data(10);
CALL courier_salary();
SELECT * FROM get_statistic();
SELECT * FROM how_much_money LIMIT 5;

RESET ROLE;
```

Ожидается: без `permission denied`.    
Факт: под `SET ROLE inspector` и отдельным подключением под `inspector` выполнены `erase_test_data()`, `insert_test_data(10)`, `courier_salary()`, `get_statistic()` (10 строк) и `how_much_money` (6 строк); ошибок `permission denied` нет. `add_product(...)` под той же ролью проверен отдельно в E.1.   
Вердикт: OK

---

## H. Оптимизация `get_statistic` (BR-11.8)

### H.1. `EXPLAIN ANALYZE` — паттерн «избыточные подзапросы»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS cnt,
       (SELECT coalesce(sum(commission), 0) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS commission_sum
FROM courier c;
```

Ожидается: два SubPlan, каждый — скан `"order"`. Время растёт линейно от числа курьеров.  
Факт: время около 0.15 мс. План: `Seq Scan on courier` (10 строк) → `SubPlan 1` (`Aggregate` → `Seq Scan on "order"`, `loops=10`, по 4 строки за цикл) и `SubPlan 2` (`Aggregate` → `Seq Scan on "order"`, `loops=10`, по 4 строки за цикл). Из 50 заказов доставленных 40, поэтому каждая из двух веток читает по 40 строк. Таблица `"order"` просканирована 20 раз, `Buffers: shared hit=261`. Время зависит от машины, важен план.  
Вердикт: OK

### H.2. `EXPLAIN ANALYZE` — паттерн «один JOIN»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       count(o.order_id) AS cnt,
       coalesce(sum(o.commission), 0) AS commission_sum
FROM courier c
LEFT JOIN "order" o ON o.courier_id = c.courier_id AND o.status = 'доставлен'
GROUP BY c.courier_id;
```

Ожидается: один `Hash Right Join` / `Hash Left Join`, один скан `"order"`. Время меньше, чем в H.1.  
Факт: время 0.044 мс. План: `HashAggregate` → `Hash Left Join` (`courier` × `"order"`) → `Seq Scan on courier` и один `Seq Scan on "order"` (из 50 заказов 40 доставленных, 10 отброшено по статусу), `Buffers: shared hit=14`.
Вердикт: OK

### H.3. Применить к `get_statistic`

```sql
EXPLAIN ANALYZE SELECT * FROM get_statistic();
```

Ожидается: без `LATERAL`, без множественных подзапросов к одной таблице, без оконных функций там, где хватает агрегата.  
Факт: время 0.397 мс. План: `Subquery Scan` → `Sort` → `CTE delivered_orders` (`Seq Scan on "order"`, из 50 строк 40 доставленных) → `CTE best_products` (`Unique` → `Incremental Sort` → `GroupAggregate` → `Nested Loop` с `Bitmap Heap Scan` по `order_structure` и `Index Scan` по `product`) → `CTE best_clients` (`Unique` → `Incremental Sort` → `GroupAggregate` → `Hash Join` с `client`) → `Hash Left Join` с `restaurant`, `restaurant_totals`, `best_products` и `best_clients`. Каждая таблица встречается в плане один раз: `"order"`, `order_structure`, `product`, `client`, `restaurant`. `Buffers: shared hit=432`. `WindowAgg`, `LATERAL` и `SubPlan` отсутствуют.  
Вердикт: OK

---

## I. Очистка и повторная генерация

### I.1. `erase_test_data` очищает всё

```sql
CALL erase_test_data();

SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'order_structure', count(*) FROM order_structure
UNION ALL SELECT 'client_address', count(*) FROM client_address
UNION ALL SELECT 'courier_pay', count(*) FROM courier_pay;
```

Ожидается: все 0.  
Факт: Все 12 таблиц вернули 0 строк.  
Вердикт: OK

### I.2. Повторный `erase_test_data` не падает

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.  
Факт: Повторный вызов прошёл без ошибок.  
Вердикт: OK

### I.3. После очистки `insert_test_data` снова работает

```sql
CALL insert_test_data(10);
SELECT count(*) FROM "order";
```

Ожидается: 50.  
Факт: `insert_test_data(10)` прошёл, в `order` 50 строк.  
Вердикт: OK

