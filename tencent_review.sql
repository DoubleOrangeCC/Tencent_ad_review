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


-- 1. 历史数据（9月1日-9月23日，用于产出和质量基准）
WITH history AS (SELECT reviewer_id,
                        ad_module,
                        SUM(1)              AS hist_total_review,
                        SUM(CASE
                                WHEN is_correct = 0 THEN
                                    CASE error_type
                                        WHEN '漏放' THEN CASE
                                                             WHEN risk_level = '高' THEN 40
                                                             WHEN risk_level = '中' THEN 20
                                                             ELSE 10
                                            END
                                        WHEN '误杀' THEN CASE
                                                             WHEN risk_level = '高' THEN 20
                                                             WHEN risk_level = '中' THEN 10
                                                             ELSE 5
                                            END
                                        ELSE 0
                                        END
                                ELSE 0 END) AS hist_quality_deduction,
                        SUM(1)              AS weight
                 FROM tencent
                 WHERE date >= '2025-09-01'
                   AND date < '2025-09-24'
                 GROUP BY reviewer_id, ad_module),

-- 2. 本周数据（9月24日-9月30日）
     this_week AS (SELECT reviewer_id,
                          ad_module,
                          SUM(1)              AS total_review,
                          SUM(review_sec)     AS total_time,
                          SUM(CASE
                                  WHEN is_correct = 0 THEN
                                      CASE error_type
                                          WHEN '漏放' THEN CASE
                                                               WHEN risk_level = '高' THEN 40
                                                               WHEN risk_level = '中' THEN 20
                                                               ELSE 10
                                              END
                                          WHEN '误杀' THEN CASE
                                                               WHEN risk_level = '高' THEN 20
                                                               WHEN risk_level = '中' THEN 10
                                                               ELSE 5
                                              END
                                          ELSE 0
                                          END
                                  ELSE 0 END) AS quality_deduction,
                          AVG(CASE risk_level
                                  WHEN '低' THEN 1
                                  WHEN '中' THEN 2
                                  WHEN '高' THEN 3
                                  ELSE 0
                              END)            AS avg_risk
                   FROM tencent
                   WHERE date >= '2025-09-24'
                     AND date <= '2025-09-30'
                   GROUP BY reviewer_id, ad_module),

-- 3. 模块分项得分（每个广告模块算出四个维度得分）
     module_scores AS (SELECT tw.reviewer_id,
                              tw.ad_module,
                              tw.total_review,
                              tw.total_time,
                              tw.quality_deduction,
                              tw.avg_risk,
                              h.weight,
                              -- 产出得分
                              LEAST(tw.total_review / NULLIF(h.hist_total_review, 0), 1) AS S_output,
                              -- 效率得分
                              CASE
                                  WHEN tw.total_time > 0 THEN (tw.total_review * 60) / tw.total_time
                                  ELSE 0 END                                             AS S_efficiency,
                              -- 质量得分（避免除以0，用COALESCE处理）
                              COALESCE(h.hist_quality_deduction / NULLIF(tw.quality_deduction, 0),
                                       1)                                                AS S_quality,
                              -- 风险得分
                              1 + 0.1 * COALESCE(tw.avg_risk, 0) / 3                     AS S_risk -- 最大风险等级数字 3
                       FROM this_week tw
                                JOIN history h
                                     ON tw.reviewer_id = h.reviewer_id
                                         AND tw.ad_module = h.ad_module),

-- 4. 每个审核员的四维度加权平均（模块内部加权）
     dim_avg AS (SELECT reviewer_id,
                        SUM(weight * S_output) / SUM(weight)     AS S_output,
                        SUM(weight * S_efficiency) / SUM(weight) AS S_efficiency,
                        SUM(weight * S_quality) / SUM(weight)    AS S_quality,
                        SUM(weight * S_risk) / SUM(weight)       AS S_risk
                 FROM module_scores
                 GROUP BY reviewer_id)

-- 5. 输出审核员四个得分模块及最终绩效
SELECT reviewer_id,
       S_output,
       S_efficiency,
       S_quality,
       S_risk,
       S_output * S_efficiency * S_quality * S_risk AS performance
FROM dim_avg
ORDER BY performance asc;


