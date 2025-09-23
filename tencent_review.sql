#缺失值
select *
from tencent
where reviewer_id is null
   or reviewer_group is null
   or start_time is null
   or end_time is null
   or review_sec is null
   or is_correct is null
   or review_result is null
   or ad_module is null
   or reject_reason is null
   or ad_id is null
   or ad_platform is null
   or risk_level is null
#无缺失值

#重复值
select *, count(*) as cnt
from tencent
group by reviewer_id, reviewer_group, start_time, end_time, review_sec, is_correct, review_result, erro_type,
         reject_reason,
         ad_id, ad_type, ad_platform, risk_level, ad_content
having count(*) > 1;
#无重复值

#异常值
select min(start_time),
       max(start_time),
       min(end_time),
       max(end_time)
from tencent;
#无异常值

#数据总览
create table 数据交叉表 as
select reviewer_group,
       ad_module,
       ad_platform,
       risk_level,
       date,
       hour,
       reviewer_id,
       count(*)                                                           as 总审核数,
       sum(review_sec)                                                    as 总耗时,
       sum(case when is_correct = 1 then 1 else 0 end)                    as 总正确数,
       sum(case when is_correct = 0 then 1 else 0 end)                    as 总错误数,
       sum(case when is_correct = 1 then 1 else 0 end) / count(*)         as 正确率,
       sum(case when review_result = '通过' then 1 else 0 end)            as 总通过数,
       sum(case when review_result = '不通过' then 1 else 0 end)          as 总不通过数,
       sum(case when review_result = '通过' then 1 else 0 end) / count(*) as 通过率
from tencent
group by date, hour, reviewer_group, ad_module, ad_platform, risk_level, reviewer_id
order by date, hour;


#平均审核耗时最短top100审核员
with cte as (select reviewer_id, avg(review_sec) as avg, row_number() over (order by avg(review_sec)) as rn
             from tencent
             group by reviewer_id)
select reviewer_id, avg, rn
from cte
where rn <= 100
   or rn >= 2900;

create table 绩效模型 as
with performance_current as
         (select reviewer_id,
                 ad_module,
                 count(*)                                                                    as cnt,
                 sum(review_sec)                                                             as time,
                 count(*) / sum(review_sec)                                                  as efficiency,
                 sum(CASE
                         WHEN is_correct = 0 AND error_type = '误杀' AND risk_level = '低' THEN 1
                         WHEN is_correct = 0 AND error_type = '误杀' AND risk_level = '中' THEN 2
                         WHEN is_correct = 0 AND error_type = '误杀' AND risk_level = '高' THEN 3
                         WHEN is_correct = 0 AND error_type = '漏放' AND risk_level = '低' THEN 2
                         WHEN is_correct = 0 AND error_type = '漏放' AND risk_level = '中' THEN 3
                         WHEN is_correct = 0 AND error_type = '漏放' AND risk_level = '高' THEN 4
                         ELSE 0
                     END) / count(*)                                                         as quality,
                 avg(case risk_level when '低' then 1 when '中' then 2 when '高' then 3 end) as risk
          from tencent
          where date between '2025-09-24' and '2025-09-30'
          group by reviewer_id, ad_module),
     performance_history as
         (select ad_module,
                 count(distinct reviewer_id) as cnt_reviewer,
                 count(*)                    as cnt,
                 sum(review_sec)             as time,
                 count(*) / sum(review_sec)  as efficiency,
                 sum(CASE
                         WHEN is_correct = 0 AND error_type = '误杀' AND risk_level = '低' THEN 1
                         WHEN is_correct = 0 AND error_type = '误杀' AND risk_level = '中' THEN 2
                         WHEN is_correct = 0 AND error_type = '误杀' AND risk_level = '高' THEN 3
                         WHEN is_correct = 0 AND error_type = '漏放' AND risk_level = '低' THEN 2
                         WHEN is_correct = 0 AND error_type = '漏放' AND risk_level = '中' THEN 3
                         WHEN is_correct = 0 AND error_type = '漏放' AND risk_level = '高' THEN 4
                         ELSE 0
                     END) / count(*)         as quality
          from tencent
          where date between '2025-09-17' and '2025-09-23'
          group by ad_module),
     module_score as (select c.reviewer_id,
                             sum(least(c.cnt / (h.cnt / cnt_reviewer), 1) * c.cnt) / sum(c.cnt) as output,
                             sum(c.efficiency / h.efficiency * c.cnt) / sum(c.cnt)            as efficiency,
                             sum((h.quality / NULLIF(c.quality, 0)) * c.cnt) / sum(c.cnt)     as quality,
                             sum((1 + (0.1 * (risk / 3))) * c.cnt) / sum(c.cnt)               as risk
                      from performance_current c
                               join performance_history h on c.ad_module = h.ad_module
                      group by c.reviewer_id)
select reviewer_id, output * efficiency * quality * risk as final_score
from module_score
order by 2 desc;

