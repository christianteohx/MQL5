"""Export optimized parameters for MQL5 and JSON formats."""
from typing import Dict
import json

class ParameterExporter:
    def export_mql5_inputs(self, params: Dict, output_path: str) -> None:
        lines = []
        for k, v in params.items():
            t = 'double' if isinstance(v, float) else 'int'
            lines.append(f'input {t} {k} = {v}; // exported')
        content = '\n'.join(lines) + '\n'
        with open(output_path, 'w') as f:
            f.write(content)

    def export_json(self, params: Dict, output_path: str) -> None:
        with open(output_path, 'w') as f:
            json.dump(params, f, indent=2)

    def generate_regime_config(self, regime_weights: Dict, regime_params: Dict) -> Dict:
        return {'weights': regime_weights, 'params': regime_params}

if __name__ == '__main__':
    print('ParameterExporter loaded')
