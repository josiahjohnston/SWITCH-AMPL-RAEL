set search_path to chile;

--select * from chile.training_sets_deleted_rows;

select * from demand_projection_daily_summaries 
WHERE num_data_points > 527 order by peak_hour_number;