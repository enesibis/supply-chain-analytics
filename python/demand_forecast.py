"""
SCM_3 - Talep Tahmini (Demand Forecasting)
XGBoost ile aylik urun bazli talep tahmini
"""

import pandas as pd
import numpy as np
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import mean_absolute_error, mean_squared_error
import xgboost as xgb
import warnings
warnings.filterwarnings('ignore')

# ── 1. VERİ YÜKLE ────────────────────────────────────────────────────────────
print("=" * 60)
print("SCM_3 TALEP TAHMİN MODELİ")
print("=" * 60)

df = pd.read_csv(r"C:\Users\enesi\supply-chain-analytics\python\demand_data.csv")
df = df.sort_values(['productID', 'subeKodu', 'yil', 'ay']).reset_index(drop=True)

print(f"\n[1] Veri yuklendi: {df.shape[0]} satir, {df['productName'].nunique()} urun, {df['subeKodu'].nunique()} sube")
print(f"    Donem: {df['yil'].min()}/{df['ay'].min():02d} - {df['yil'].max()}/{df['ay'].max():02d}")

# ── 2. TAM GRID OLUŞTUR (boş ayları doldur) ──────────────────────────────────
# Her urun x sube x ay kombinasyonu icin tam grid — eksik aylar 0 ile doldurulur
products   = df[['productID', 'productName', 'categoryName']].drop_duplicates()
subes      = df['subeKodu'].unique()
periods    = [(y, m) for y in [2022, 2023, 2024] for m in range(1, 13)]

grid_rows = []
for _, prod in products.iterrows():
    for sube in subes:
        for yil, ay in periods:
            grid_rows.append({
                'productID': prod['productID'],
                'productName': prod['productName'],
                'categoryName': prod['categoryName'],
                'subeKodu': sube,
                'yil': yil,
                'ay': ay,
            })

grid = pd.DataFrame(grid_rows)
df_full = grid.merge(
    df[['productID', 'subeKodu', 'yil', 'ay', 'toplamMiktar', 'siparisAdet']],
    on=['productID', 'subeKodu', 'yil', 'ay'],
    how='left'
).fillna({'toplamMiktar': 0, 'siparisAdet': 0})

print(f"    Tam grid: {df_full.shape[0]} satir (eksik aylar 0 ile dolduruldu)")

# ── 3. FEATURE ENGINEERING ───────────────────────────────────────────────────
print("\n[2] Feature engineering...")

# Zaman index (sirali)
df_full['donem_idx'] = (df_full['yil'] - 2022) * 12 + df_full['ay']

# Lag features (onceki aylar)
df_full = df_full.sort_values(['productID', 'subeKodu', 'donem_idx'])
for lag in [1, 2, 3, 6, 12]:
    df_full[f'lag_{lag}'] = df_full.groupby(['productID', 'subeKodu'])['toplamMiktar'].shift(lag)

# Rolling istatistikler
df_full['rolling_mean_3']  = df_full.groupby(['productID', 'subeKodu'])['toplamMiktar'].shift(1).rolling(3).mean().values
df_full['rolling_mean_6']  = df_full.groupby(['productID', 'subeKodu'])['toplamMiktar'].shift(1).rolling(6).mean().values
df_full['rolling_std_3']   = df_full.groupby(['productID', 'subeKodu'])['toplamMiktar'].shift(1).rolling(3).std().values

# Mevsimsellik
df_full['is_q4']        = df_full['ay'].isin([10, 11, 12]).astype(int)  # Q4 yuksek
df_full['is_winter']    = df_full['ay'].isin([1, 2, 3]).astype(int)     # Kis dusuk
df_full['ay_sin']       = np.sin(2 * np.pi * df_full['ay'] / 12)
df_full['ay_cos']       = np.cos(2 * np.pi * df_full['ay'] / 12)

# Trend
df_full['trend'] = df_full['donem_idx']

# Kategorik encode
le_sube = LabelEncoder()
le_cat  = LabelEncoder()
le_prod = LabelEncoder()
df_full['sube_enc']    = le_sube.fit_transform(df_full['subeKodu'])
df_full['cat_enc']     = le_cat.fit_transform(df_full['categoryName'])
df_full['product_enc'] = le_prod.fit_transform(df_full['productName'])

# Sube buyukluk agirligı
sube_weight = {'IST-001': 1.40, 'ANK-001': 1.10, 'IZM-001': 1.00, 'BRS-001': 0.75}
df_full['sube_weight'] = df_full['subeKodu'].map(sube_weight)

features = [
    'ay', 'yil', 'trend',
    'sube_enc', 'cat_enc', 'product_enc', 'sube_weight',
    'lag_1', 'lag_2', 'lag_3', 'lag_6', 'lag_12',
    'rolling_mean_3', 'rolling_mean_6', 'rolling_std_3',
    'is_q4', 'is_winter', 'ay_sin', 'ay_cos',
]

# Lag olan satirlar — en az lag_1 dolu olmali (2022 Subat'tan itibaren)
df_model = df_full.dropna(subset=['lag_1', 'lag_2', 'lag_3']).copy()
print(f"    Model icin {df_model.shape[0]} satir hazir")

# ── 4. TRAIN / TEST SPLIT ─────────────────────────────────────────────────────
# 2022-2023: train, 2024: test (gercek veri ile karsilastirma)
train = df_model[df_model['yil'].isin([2022, 2023])]
test  = df_model[df_model['yil'] == 2024]

X_train = train[features]
y_train = train['toplamMiktar']
X_test  = test[features]
y_test  = test['toplamMiktar']

print(f"\n[3] Train/Test split:")
print(f"    Train: {len(X_train)} satir (2022-2023)")
print(f"    Test:  {len(X_test)} satir (2024)")

# ── 5. MODEL EĞİTİMİ ─────────────────────────────────────────────────────────
print("\n[4] XGBoost modeli egitiliyor...")

model = xgb.XGBRegressor(
    n_estimators=500,
    max_depth=6,
    learning_rate=0.05,
    subsample=0.8,
    colsample_bytree=0.8,
    min_child_weight=3,
    reg_alpha=0.1,
    reg_lambda=1.0,
    random_state=42,
    verbosity=0,
)

model.fit(
    X_train, y_train,
    eval_set=[(X_test, y_test)],
    verbose=False,
)

# ── 6. DEĞERLENDİRME ─────────────────────────────────────────────────────────
y_pred = model.predict(X_test)
y_pred = np.maximum(y_pred, 0)  # negatif tahmin olmaz

mae  = mean_absolute_error(y_test, y_pred)
rmse = np.sqrt(mean_squared_error(y_test, y_pred))
mape = np.mean(np.abs((y_test - y_pred) / (y_test + 1))) * 100

print(f"\n[5] Model Performansi (2024 test seti):")
print(f"    MAE  : {mae:.2f}  (ortalama mutlak hata)")
print(f"    RMSE : {rmse:.2f}  (karekok ortalama kare hata)")
print(f"    MAPE : {mape:.1f}% (ortalama yuzde hata)")

# Feature importance
feat_imp = pd.DataFrame({
    'feature': features,
    'importance': model.feature_importances_
}).sort_values('importance', ascending=False)

print(f"\n    En onemli 8 feature:")
for _, row in feat_imp.head(8).iterrows():
    bar = '=' * int(row['importance'] * 200)
    print(f"    {row['feature']:<20} {bar} {row['importance']:.4f}")

# ── 7. 2025 TAHMİNLERİ ───────────────────────────────────────────────────────
print("\n[6] 2025 tahmini uretiliyor...")

# Son bilinan degerleri al
last_known = df_full[df_full['yil'] == 2024].copy()

forecast_rows = []

for month in range(1, 13):
    for prod_id in df_full['productID'].unique():
        for sube in subes:
            # Bu urun+sube icin gecmis verileri al
            hist = df_full[
                (df_full['productID'] == prod_id) &
                (df_full['subeKodu'] == sube)
            ].sort_values('donem_idx')

            if len(hist) == 0:
                continue

            prod_info = hist.iloc[0]
            donem_idx = (2025 - 2022) * 12 + month

            # Lag degerleri gecmisten hesapla
            all_vals = hist['toplamMiktar'].values

            def get_lag(n):
                # 2025 ay icin n ay geri bak
                # 2025 Ocak (donem 37) icin lag_1 = 2024 Aralik (donem 36)
                target_donem = donem_idx - n
                row = hist[hist['donem_idx'] == target_donem]
                if len(row) > 0:
                    return row['toplamMiktar'].values[0]
                return np.mean(all_vals[-3:]) if len(all_vals) >= 3 else 0

            lag1  = get_lag(1)
            lag2  = get_lag(2)
            lag3  = get_lag(3)
            lag6  = get_lag(6)
            lag12 = get_lag(12)

            recent = [get_lag(i) for i in range(1, 4)]
            recent6 = [get_lag(i) for i in range(1, 7)]

            row_feat = {
                'ay': month,
                'yil': 2025,
                'trend': donem_idx,
                'sube_enc': le_sube.transform([sube])[0],
                'cat_enc': le_cat.transform([prod_info['categoryName']])[0],
                'product_enc': le_prod.transform([prod_info['productName']])[0],
                'sube_weight': sube_weight.get(sube, 1.0),
                'lag_1': lag1, 'lag_2': lag2, 'lag_3': lag3,
                'lag_6': lag6, 'lag_12': lag12,
                'rolling_mean_3': np.mean(recent),
                'rolling_mean_6': np.mean(recent6),
                'rolling_std_3': np.std(recent) if len(recent) > 1 else 0,
                'is_q4': int(month in [10, 11, 12]),
                'is_winter': int(month in [1, 2, 3]),
                'ay_sin': np.sin(2 * np.pi * month / 12),
                'ay_cos': np.cos(2 * np.pi * month / 12),
            }

            pred = max(0, model.predict(pd.DataFrame([row_feat]))[0])

            forecast_rows.append({
                'yil': 2025,
                'ay': month,
                'subeKodu': sube,
                'productID': prod_id,
                'productName': prod_info['productName'],
                'categoryName': prod_info['categoryName'],
                'tahmin_miktar': round(pred, 1),
            })

forecast_df = pd.DataFrame(forecast_rows)

# ── 8. SONUÇLARI KAYDET ──────────────────────────────────────────────────────
out_path = r"C:\Users\enesi\supply-chain-analytics\python\forecast_2025.csv"
forecast_df.to_csv(out_path, index=False, encoding='utf-8-sig')
print(f"    forecast_2025.csv kaydedildi: {len(forecast_df)} satir")

# Ozet: en yuksek tahmin edilen urunler (2025 yili toplami)
print(f"\n[7] 2025 Tahmin Ozeti (Tum Subeler, Yillik Toplam):")
summary = (
    forecast_df.groupby('productName')['tahmin_miktar']
    .sum()
    .sort_values(ascending=False)
    .head(10)
)
for prod, val in summary.items():
    bar = '=' * int(val / summary.max() * 30)
    print(f"    {prod:<30} {bar} {val:,.0f}")

print(f"\n[8] 2025 Q1 Tahmini (Ocak-Mart, Tum Subeler):")
q1 = forecast_df[forecast_df['ay'].isin([1, 2, 3])].groupby('subeKodu')['tahmin_miktar'].sum()
for sube, val in q1.sort_values(ascending=False).items():
    print(f"    {sube}: {val:,.0f} adet")

print(f"\nTamamlandi!")
print(f"  - Model: XGBoost ({model.n_estimators} agac, derinlik {model.max_depth})")
print(f"  - MAE: {mae:.1f} | RMSE: {rmse:.1f} | MAPE: {mape:.1f}%")
print(f"  - Tahmin dosyasi: forecast_2025.csv")
