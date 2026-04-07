"""
SCM_3 - Talep Tahmini v3
Urun bazli aylik toplam talep tahmini (tum subeler birlesik)
Sube dagilimi tahmin sonrasi agirlik ile uygulanir.
"""

import pandas as pd
import numpy as np
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import TimeSeriesSplit
import xgboost as xgb
import warnings
warnings.filterwarnings('ignore')

print("=" * 60)
print("SCM_3 TALEP TAHMİN MODELİ v3")
print("Urun Bazli (Tum Subeler Toplam)")
print("=" * 60)

# ── 1. VERİ YÜKLE ─────────────────────────────────────────────────────────
df = pd.read_csv(r"C:\Users\enesi\supply-chain-analytics\python\demand_data.csv")

# Urun + ay bazinda tum subeler toplam
df_prod = (
    df.groupby(['yil', 'ay', 'productID', 'productName', 'categoryName'])
    .agg(toplamMiktar=('toplamMiktar', 'sum'),
         toplamCiro=('toplamCiro', 'sum'),
         siparisAdet=('siparisAdet', 'sum'))
    .reset_index()
    .sort_values(['productID', 'yil', 'ay'])
    .reset_index(drop=True)
)

# Tam grid: her urun icin 36 ay
products = df_prod[['productID','productName','categoryName']].drop_duplicates()
periods  = [(y,m) for y in [2022,2023,2024] for m in range(1,13)]
grid = pd.DataFrame(
    [{'productID':r.productID,'productName':r.productName,'categoryName':r.categoryName,
      'yil':y,'ay':m} for _,r in products.iterrows() for y,m in periods]
)
df_full = grid.merge(df_prod, on=['productID','productName','categoryName','yil','ay'], how='left')
df_full = df_full.fillna({'toplamMiktar':0,'toplamCiro':0,'siparisAdet':0})
df_full['donem_idx'] = (df_full['yil']-2022)*12 + df_full['ay']
df_full = df_full.sort_values(['productID','donem_idx']).reset_index(drop=True)

print(f"\n[1] Urun-ay grid: {len(df_full)} satir | {df_full['productID'].nunique()} urun")
print(f"    Sifir olmayan: {(df_full['toplamMiktar']>0).sum()} satir")
print(f"    Ortalama miktar: {df_full[df_full.toplamMiktar>0]['toplamMiktar'].mean():.1f}")

# ── 2. FEATURE ENGINEERING ─────────────────────────────────────────────────
grp = df_full.groupby('productID')['toplamMiktar']

for lag in [1, 2, 3, 6, 12]:
    df_full[f'lag_{lag}'] = grp.shift(lag)

df_full['roll_mean_3']  = grp.shift(1).transform(lambda x: x.rolling(3,  min_periods=1).mean())
df_full['roll_mean_6']  = grp.shift(1).transform(lambda x: x.rolling(6,  min_periods=1).mean())
df_full['roll_mean_12'] = grp.shift(1).transform(lambda x: x.rolling(12, min_periods=1).mean())
df_full['roll_std_3']   = grp.shift(1).transform(lambda x: x.rolling(3,  min_periods=2).std()).fillna(0)
df_full['roll_max_3']   = grp.shift(1).transform(lambda x: x.rolling(3,  min_periods=1).max())

# Mevsimsellik
df_full['ay_sin']    = np.sin(2 * np.pi * df_full['ay'] / 12)
df_full['ay_cos']    = np.cos(2 * np.pi * df_full['ay'] / 12)
df_full['is_q4']     = df_full['ay'].isin([10, 11, 12]).astype(int)
df_full['is_q1']     = df_full['ay'].isin([1, 2, 3]).astype(int)
df_full['trend']     = df_full['donem_idx']

# Urun encode
le_cat  = LabelEncoder()
le_prod = LabelEncoder()
df_full['cat_enc']     = le_cat.fit_transform(df_full['categoryName'])
df_full['product_enc'] = le_prod.fit_transform(df_full['productName'])

FEATURES = [
    'ay', 'yil', 'trend',
    'cat_enc', 'product_enc',
    'lag_1', 'lag_2', 'lag_3', 'lag_6', 'lag_12',
    'roll_mean_3', 'roll_mean_6', 'roll_mean_12',
    'roll_std_3', 'roll_max_3',
    'is_q4', 'is_q1', 'ay_sin', 'ay_cos',
]

df_model = df_full.dropna(subset=['lag_1','lag_2','lag_3']).copy()
print(f"\n[2] Feature engineering tamamlandi: {len(FEATURES)} feature")

# ── 3. TRAIN / TEST SPLIT ──────────────────────────────────────────────────
# 2022-2023: train (24 ay), 2024: test (12 ay)
train = df_model[df_model['yil'].isin([2022, 2023])]
test  = df_model[df_model['yil'] == 2024]

X_train, y_train = train[FEATURES], train['toplamMiktar']
X_test,  y_test  = test[FEATURES],  test['toplamMiktar']

print(f"\n[3] Train/Test: {len(train)} train | {len(test)} test")
print(f"    Train sifir olmayan: {(y_train>0).sum()} / {len(y_train)}")
print(f"    Test  sifir olmayan: {(y_test>0).sum()} / {len(y_test)}")

# ── 4. TIME SERIES CROSS VALIDATION ───────────────────────────────────────
print("\n[4] TimeSeriesSplit CV (5 fold, train+test birlikte)...")

df_all_sorted = df_model.sort_values('donem_idx').reset_index(drop=True)
X_all = df_all_sorted[FEATURES]
y_all = df_all_sorted['toplamMiktar']

tscv = TimeSeriesSplit(n_splits=5, test_size=len(products)*2)

params = dict(
    n_estimators=400,
    max_depth=4,
    learning_rate=0.08,
    subsample=0.85,
    colsample_bytree=0.85,
    min_child_weight=3,
    reg_alpha=0.3,
    reg_lambda=1.5,
    random_state=42,
    verbosity=0,
)

cv_maes = []; cv_r2s = []

for fold, (tr_idx, te_idx) in enumerate(tscv.split(X_all), 1):
    m = xgb.XGBRegressor(**params)
    m.fit(X_all.iloc[tr_idx], y_all.iloc[tr_idx], verbose=False)
    preds = np.maximum(m.predict(X_all.iloc[te_idx]), 0)
    y_te  = y_all.iloc[te_idx]
    nz    = y_te > 0
    if nz.sum() > 1:
        mae = mean_absolute_error(y_te[nz], preds[nz])
        r2  = r2_score(y_te[nz], preds[nz])
        cv_maes.append(mae); cv_r2s.append(r2)
        print(f"    Fold {fold}: MAE={mae:.2f}  R2={r2:.3f}  (n={nz.sum()})")

print(f"\n    CV Ortalama → MAE: {np.mean(cv_maes):.2f} ± {np.std(cv_maes):.2f}")
print(f"                  R2:  {np.mean(cv_r2s):.3f}")

# ── 5. FİNAL MODEL ve TEST SONUCU ─────────────────────────────────────────
print("\n[5] Final model egitiliyor (2022-2023) ve 2024 test ediliyor...")

final = xgb.XGBRegressor(**params)
final.fit(X_train, y_train, verbose=False)
y_pred = np.maximum(final.predict(X_test), 0)

nz = y_test > 0
mae_nz  = mean_absolute_error(y_test[nz], y_pred[nz])
rmse_nz = np.sqrt(mean_squared_error(y_test[nz], y_pred[nz]))
r2_nz   = r2_score(y_test[nz], y_pred[nz])
mape_nz = np.mean(np.abs((y_test[nz] - y_pred[nz]) / y_test[nz])) * 100

print(f"\n    2024 Test Sonucu ({nz.sum()} gercek siparis satiri):")
print(f"    MAE      : {mae_nz:.2f}")
print(f"    RMSE     : {rmse_nz:.2f}")
print(f"    R2       : {r2_nz:.3f}  ({r2_nz*100:.1f}% varyans aciklaniyor)")
print(f"    MAPE     : %{mape_nz:.1f}")
print(f"    Dogruluk : %{100-mape_nz:.1f}")
print(f"    Gercek ort: {y_test[nz].mean():.2f} | Tahmin ort: {y_pred[nz].mean():.2f}")

# Feature importance
feat_imp = pd.DataFrame({'feature':FEATURES, 'importance':final.feature_importances_})
feat_imp = feat_imp.sort_values('importance', ascending=False)
print(f"\n    Top 8 Feature:")
for _, r in feat_imp.head(8).iterrows():
    bar = '=' * int(r['importance'] * 300)
    print(f"    {r['feature']:<18} {bar} {r['importance']:.4f}")

# ── 6. 2025 TAHMİNİ ───────────────────────────────────────────────────────
print("\n[6] 2025 urun bazli aylik tahmin...")

SUBE_W = {'IST-001':1.40,'ANK-001':1.10,'IZM-001':1.00,'BRS-001':0.75}
sube_total = sum(SUBE_W.values())

forecast_rows = []

for _, prod in products.iterrows():
    hist = df_full[df_full['productID']==prod['productID']].sort_values('donem_idx')
    vals = list(hist['toplamMiktar'].values)

    for month in range(1, 13):
        donem_idx = 36 + month

        def gl(n):
            pos = len(vals) - n
            return float(vals[pos]) if pos >= 0 else float(np.mean(vals[-3:]))

        recent3  = [gl(i) for i in range(1,4)]
        recent6  = [gl(i) for i in range(1,7)]
        recent12 = [gl(i) for i in range(1,13)]

        row = {
            'ay': month, 'yil': 2025, 'trend': donem_idx,
            'cat_enc':     le_cat.transform([prod['categoryName']])[0],
            'product_enc': le_prod.transform([prod['productName']])[0],
            'lag_1': gl(1), 'lag_2': gl(2), 'lag_3': gl(3),
            'lag_6': gl(6), 'lag_12': gl(12),
            'roll_mean_3':  np.mean(recent3),
            'roll_mean_6':  np.mean(recent6),
            'roll_mean_12': np.mean(recent12),
            'roll_std_3':   np.std(recent3) if len(recent3)>1 else 0,
            'roll_max_3':   max(recent3),
            'is_q4':     int(month in [10,11,12]),
            'is_q1':     int(month in [1,2,3]),
            'ay_sin': np.sin(2*np.pi*month/12),
            'ay_cos': np.cos(2*np.pi*month/12),
        }

        total_pred = max(0, round(float(final.predict(pd.DataFrame([row]))[0]), 1))
        vals.append(total_pred)

        # Sube dagilimi: agirlik oranina gore
        for sube, w in SUBE_W.items():
            sube_pred = round(total_pred * w / sube_total, 1)
            forecast_rows.append({
                'yil': 2025, 'ay': month,
                'subeKodu': sube,
                'productID': prod['productID'],
                'productName': prod['productName'],
                'categoryName': prod['categoryName'],
                'tahmin_toplam': total_pred,
                'tahmin_sube': sube_pred,
            })

forecast_df = pd.DataFrame(forecast_rows)
forecast_df.to_csv(
    r"C:\Users\enesi\supply-chain-analytics\python\forecast_2025.csv",
    index=False, encoding='utf-8-sig'
)

# ── 7. SONUÇLAR ───────────────────────────────────────────────────────────
print(f"\n[7] 2025 Yillik Tahmin - En Yuksek 10 Urun:")
prod_sum = forecast_df.groupby('productName')['tahmin_toplam'].sum().div(4).sort_values(ascending=False).head(10)
for p, v in prod_sum.items():
    bar = '=' * int(v / prod_sum.max() * 30)
    print(f"    {p:<32} {bar} {v:.0f}")

print(f"\n[8] 2025 Sube Bazli Yillik Tahmin:")
sube_sum = forecast_df.groupby('subeKodu')['tahmin_sube'].sum().sort_values(ascending=False)
for s, v in sube_sum.items():
    pct = v / sube_sum.sum() * 100
    print(f"    {s}: {v:.0f} adet  (%{pct:.0f})")

print(f"\n[9] 2025 Aylik Toplam Talep Trendi:")
monthly = forecast_df.groupby('ay')['tahmin_toplam'].sum().div(4)
for ay, v in monthly.items():
    bar = '=' * int(v / monthly.max() * 25)
    print(f"    {ay:>2}. ay: {bar} {v:.0f}")

print(f"\n{'='*60}")
print(f"SONUC")
print(f"{'='*60}")
print(f"  Model    : XGBoost, urun bazli aylik toplam talep")
print(f"  CV MAE   : {np.mean(cv_maes):.2f} +/- {np.std(cv_maes):.2f}  (sifir olmayan satirlar)")
print(f"  CV R2    : {np.mean(cv_r2s):.3f}")
print(f"  Test MAE : {mae_nz:.2f}  |  R2: {r2_nz:.3f}  |  Dogruluk: %{100-mape_nz:.1f}")
print(f"  forecast_2025.csv: {len(forecast_df)} satir")
