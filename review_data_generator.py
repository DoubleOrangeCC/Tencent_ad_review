import csv
import random
import numpy as np
from datetime import datetime, timedelta

# ----------------------------
# 参数
# ----------------------------
RANDOM_SEED = 42
NUM_REVIEWERS = 3000
START_DATE = datetime(2025, 9, 1)
END_DATE = datetime(2025, 9, 30)
WORK_SHIFT_START_HOUR = 9
WORK_SHIFT_END_HOUR = 20
OUTPUT_FILENAME = "review_logs_sep2025.csv"

random.seed(RANDOM_SEED)
np.random.seed(RANDOM_SEED)

# 部门/审核组
departments = ['AI', '金融', '电商', '游戏', '社交', '教育', '汽车', '医疗']

# 广告模块
ad_modules = ['AI领域', '金融广告', '电商推广', '游戏营销', '社交平台', '教育培训', '汽车出行', '医疗健康']

# 广告平台
ad_platforms = ['朋友圈', '公众号', '搜索页', '信息流', '视频流', '小程序']

# 审核不通过原因
reject_reasons = ['夸大宣传', '虚假信息', '违规词汇', '未标注广告', '其他']

# 风险等级
risk_levels = ['高', '中', '低']

# ----------------------------
# 审核员生成
# ----------------------------
reviewers = []
for i in range(1, NUM_REVIEWERS + 1):
    dept = random.choice(departments)
    mean_eff = int(np.clip(np.random.normal(280, 60), 60, 900))
    r = random.random()
    if r < 0.05: mean_eff = random.randint(60, 120)
    elif r < 0.10: mean_eff = random.randint(600, 900)
    mean_acc = float(np.clip(np.random.beta(7,3), 0.4,0.99))
    r2 = random.random()
    if r2 < 0.05: mean_acc = float(np.round(random.uniform(0.40,0.55),3))
    elif r2 <0.10: mean_acc = float(np.round(random.uniform(0.95,0.99),3))
    mean_err = 1.0 - mean_acc
    resilience = float(np.clip(np.random.normal(0.72,0.15),0.3,0.99))
    weekend_shift = random.random() < 0.3
    reviewers.append({
        'reviewer_id': i,
        'reviewer_group': dept,
        'mean_efficiency': mean_eff,
        'mean_error_rate': mean_err,
        'resilience_factor': resilience,
        'weekend_shift': weekend_shift
    })

# ----------------------------
# 时间段影响
# ----------------------------
TIME_FACTORS = {
    'start_of_day': {'hours': range(9,10), 'duration':1.10,'error':1.05},
    'afternoon_dip': {'hours': range(13,15), 'duration':1.15,'error':1.10},
    'end_of_day': {'hours': range(18,20), 'duration':0.90,'error':1.20},
    'weekend': {'weekday':[5,6],'duration':1.05,'error':1.10}
}

# ----------------------------
# 写 CSV
# ----------------------------
fieldnames = [
    "reviewer_id","reviewer_group","start_time","end_time","review_sec","is_correct",
    "review_result","error_type","ad_module","reject_reason","ad_id","ad_platform","risk_level",
    "date","hour"
]

with open(OUTPUT_FILENAME, "w", newline="", encoding="utf-8-sig") as f:
    writer = csv.writer(f)
    writer.writerow(fieldnames)

log_counter = 0
current_date = START_DATE
one_day = timedelta(days=1)

while current_date <= END_DATE:
    weekday = current_date.weekday()
    print(f"Generating {current_date.strftime('%Y-%m-%d')} ...")
    with open(OUTPUT_FILENAME, "a", newline="", encoding="utf-8-sig") as f:
        writer = csv.writer(f)
        for reviewer in reviewers:
            is_weekend = weekday >=5
            if is_weekend and not reviewer['weekend_shift']:
                continue
            work_factor = float(np.clip(np.random.normal(1.0,0.12),0.6,1.4))
            shift_start = datetime.combine(current_date, datetime.min.time()) + timedelta(hours=WORK_SHIFT_START_HOUR)
            shift_end = datetime.combine(current_date, datetime.min.time()) + timedelta(hours=WORK_SHIFT_END_HOUR)
            avg_eff = reviewer['mean_efficiency']
            expected_tasks = int(np.clip(((WORK_SHIFT_END_HOUR-WORK_SHIFT_START_HOUR)*3600)/avg_eff*work_factor,3,2000))
            if expected_tasks < 50:
                daily_tasks = int(np.clip(np.random.poisson(max(5,expected_tasks)),3,2000))
            else:
                daily_tasks = int(np.clip(np.random.poisson(expected_tasks),3,2000))
            daily_tasks = min(daily_tasks,2500)
            task_count=0
            current_time=shift_start
            while task_count<daily_tasks and current_time<shift_end:
                base_sd = max(8.0, avg_eff*0.12)
                base_duration = float(np.clip(np.random.normal(avg_eff, base_sd),10.0,3600.0))
                hour = current_time.hour
                minute = current_time.minute
                duration_multiplier=1.0
                error_multiplier=1.0
                # 时间段影响
                if hour in TIME_FACTORS['start_of_day']['hours']:
                    duration_multiplier*=TIME_FACTORS['start_of_day']['duration']
                    error_multiplier*=TIME_FACTORS['start_of_day']['error']
                if hour in TIME_FACTORS['afternoon_dip']['hours']:
                    if hour==13 and minute<30:
                        duration_multiplier*=(1+(TIME_FACTORS['afternoon_dip']['duration']-1)*0.5)
                        error_multiplier*=(1+(TIME_FACTORS['afternoon_dip']['error']-1)*0.5)
                    else:
                        duration_multiplier*=TIME_FACTORS['afternoon_dip']['duration']
                        error_multiplier*=TIME_FACTORS['afternoon_dip']['error']
                if hour in TIME_FACTORS['end_of_day']['hours']:
                    duration_multiplier*=TIME_FACTORS['end_of_day']['duration']
                    error_multiplier*=TIME_FACTORS['end_of_day']['error']
                if is_weekend:
                    duration_multiplier*=TIME_FACTORS['weekend']['duration']
                    error_multiplier*=TIME_FACTORS['weekend']['error']
                r=reviewer['resilience_factor']
                effective_duration_mult=1.0+(duration_multiplier-1.0)*(1.0-r)
                effective_error_mult=1.0+(error_multiplier-1.0)*(1.0-r)
                final_duration=float(np.clip(np.random.normal(base_duration*effective_duration_mult,base_duration*0.07),5.0,7200.0))
                duration_sec=int(round(final_duration))
                # 广告是否本来应该通过（模拟真实风险/违规）
                ad_should_pass = random.random() < 0.8
                base_err=reviewer['mean_error_rate']
                adjusted_error_rate=float(np.clip(base_err*effective_error_mult,0.0001,0.95))
                is_correct = 1 if random.random() > adjusted_error_rate else 0
                # 审核结果
                if is_correct:
                    review_result = '通过' if ad_should_pass else '不通过'
                else:
                    review_result = '不通过' if ad_should_pass else '通过'
                # 错审类型
                if is_correct:
                    error_type='无'
                else:
                    if ad_should_pass:
                        error_type='误杀'
                    else:
                        error_type='漏放'
                reject_reason='无' if review_result=='通过' else random.choice(reject_reasons)
                ad_module=random.choice(ad_modules)
                ad_id=random.randint(100000,999999)
                ad_platform=random.choice(ad_platforms)
                risk_level=random.choice(risk_levels)
                log_counter+=1
                writer.writerow([
                    reviewer['reviewer_id'],
                    reviewer['reviewer_group'],
                    current_time.strftime("%Y-%m-%d %H:%M:%S"),
                    (current_time+timedelta(seconds=duration_sec)).strftime("%Y-%m-%d %H:%M:%S"),
                    duration_sec,
                    is_correct,
                    review_result,
                    error_type,
                    ad_module,
                    reject_reason,
                    ad_id,
                    ad_platform,
                    risk_level,
                    current_date.strftime("%Y-%m-%d"),
                    current_time.hour
                ])
                current_time+=timedelta(seconds=duration_sec)
                task_count+=1
    current_date+=one_day

print("🎉 数据生成完成，文件:", OUTPUT_FILENAME)
