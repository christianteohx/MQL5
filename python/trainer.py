"""Training utilities: HMM training, classifiers, walk-forward validation, save/load."""
from typing import Any, Dict, List, Tuple
import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, f1_score
from hmmlearn.hmm import GaussianHMM

class RegimeTrainer:
    def train_hmm(self, features: pd.DataFrame, n_states: int = 3, cov_type: str = 'full') -> Tuple[GaussianHMM, np.ndarray]:
        X = features.select_dtypes(include=[np.number]).fillna(0).values
        model = GaussianHMM(n_components=n_states, covariance_type=cov_type, n_iter=200)
        model.fit(X)
        trans = model.transmat_
        return model, trans

    def train_classifier(self, X: pd.DataFrame, y: pd.Series, model_type: str = 'rf') -> Any:
        if model_type == 'rf':
            m = RandomForestClassifier(n_estimators=100, random_state=42)
        else:
            m = LogisticRegression(max_iter=500)
        m.fit(X.fillna(0).values, y.values)
        return m

    def walk_forward_validate(self, data: pd.DataFrame, label_col: str, feature_cols: List[str], train_window: int = 252*2, test_window: int = 63, step: int = 63) -> List[Dict]:
        n = len(data)
        results = []
        start = 0
        while start + train_window + test_window <= n:
            train_idx = range(start, start + train_window)
            test_idx = range(start + train_window, start + train_window + test_window)
            train = data.iloc[train_idx]
            test = data.iloc[test_idx]
            X_train = train[feature_cols]
            y_train = train[label_col]
            X_test = test[feature_cols]
            y_test = test[label_col]
            clf = self.train_classifier(X_train, y_train)
            preds = clf.predict(X_test.fillna(0).values)
            acc = accuracy_score(y_test, preds)
            f1 = f1_score(y_test, preds, average='weighted')
            results.append({'train_idx': (start, start+train_window-1), 'test_idx': (start+train_window, start+train_window+test_window-1), 'model': clf, 'accuracy': acc, 'f1': f1})
            start += step
        return results

    def save_model(self, model: Any, path: str) -> None:
        joblib.dump(model, path)

    def load_model(self, path: str) -> Any:
        return joblib.load(path)

if __name__ == '__main__':
    print('RegimeTrainer loaded')
