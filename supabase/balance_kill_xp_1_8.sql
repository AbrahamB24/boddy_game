-- Balance pass 2026-11-02: kill XP exponent 1.3 -> 1.8.
--
-- Why: a campaign probe (every path battle cleared once, XP split across the
-- party, 1.25x average star bonus) showed the team falling further and
-- further behind its enemies with 9 * L^1.3:
--
--   battle   enemy Lv   team Lv @1.3   team Lv @1.8
--     10        5            4              5
--     30       15            9             13
--     57       32           14             21
--     76       41           17             27
--
-- At 1.3 fights in region 2+ cost 60-85 % HP each and the auto-battle starts
-- losing. Battles 1-10 are unchanged by the new value.
--
-- Only the one key is touched; every other XP dial in the row stays as it is.
-- To undo: run the same statement with 1.3, or change it in
-- Dev Mode > Species budget > XP.

update public.game_config
set value = jsonb_set(value, '{killExponent}', '1.8'::jsonb, true)
where key = 'xp_balance';
