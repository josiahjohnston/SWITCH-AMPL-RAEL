select * from scenarios_v3 where scenario_id > 9000;
-- Important notes about transmission_capital_cost_per_mwh:
-- For future scenarios, it should be transmission_capital_cost_per_mwh * 1.15

alter table scenarios_v3 add column dollar_base_year INT;

update scenarios_v3 set dollar_base_year = 2007;



