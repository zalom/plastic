-- Every stored time is UTC, written with Z: each time with an offset becomes its UTC time. A date, a blank and a time
-- that names no real moment, such as hour 25, stay as they are.
UPDATE "command_runs" SET "started_at" = strftime('%Y-%m-%dT%H:%M:%SZ', "started_at") WHERE "started_at" GLOB '????-??-??T??:??:??[+-]??:??' AND strftime('%Y-%m-%dT%H:%M:%SZ', "started_at") IS NOT NULL;
UPDATE "command_runs" SET "updated_at" = strftime('%Y-%m-%dT%H:%M:%SZ', "updated_at") WHERE "updated_at" GLOB '????-??-??T??:??:??[+-]??:??' AND strftime('%Y-%m-%dT%H:%M:%SZ', "updated_at") IS NOT NULL;
UPDATE "sessions" SET "started_at" = strftime('%Y-%m-%dT%H:%M:%SZ', "started_at") WHERE "started_at" GLOB '????-??-??T??:??:??[+-]??:??' AND strftime('%Y-%m-%dT%H:%M:%SZ', "started_at") IS NOT NULL;
UPDATE "sessions" SET "last_turn_at" = strftime('%Y-%m-%dT%H:%M:%SZ', "last_turn_at") WHERE "last_turn_at" GLOB '????-??-??T??:??:??[+-]??:??' AND strftime('%Y-%m-%dT%H:%M:%SZ', "last_turn_at") IS NOT NULL;
UPDATE "sessions" SET "ended_at" = strftime('%Y-%m-%dT%H:%M:%SZ', "ended_at") WHERE "ended_at" GLOB '????-??-??T??:??:??[+-]??:??' AND strftime('%Y-%m-%dT%H:%M:%SZ', "ended_at") IS NOT NULL;
UPDATE "printed" SET "at" = strftime('%Y-%m-%dT%H:%M:%SZ', "at") WHERE "at" GLOB '????-??-??T??:??:??[+-]??:??' AND strftime('%Y-%m-%dT%H:%M:%SZ', "at") IS NOT NULL;
UPDATE "chat_messages" SET "at" = strftime('%Y-%m-%dT%H:%M:%SZ', "at") WHERE "at" GLOB '????-??-??T??:??:??[+-]??:??' AND strftime('%Y-%m-%dT%H:%M:%SZ', "at") IS NOT NULL;
UPDATE "store_migrations" SET "at" = strftime('%Y-%m-%dT%H:%M:%SZ', "at") WHERE "at" GLOB '????-??-??T??:??:??[+-]??:??' AND strftime('%Y-%m-%dT%H:%M:%SZ', "at") IS NOT NULL;
