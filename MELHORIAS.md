# Pontos a Melhorar - Planter UNSW-NB15

Este documento lista melhorias futuras para o pipeline de classificação in-network, baseado nas análises do preprocessamento ML.

---

## 🎯 Foco Atual

**Objetivo:** Rodar Planter com UNSW-NB15 no BMv2
- ✅ Pipeline básico de preparação de dados
- ✅ Treinamento de Decision Tree
- ✅ Geração de código P4
- ✅ Deploy no BMv2

---

## 🚀 Melhorias Futuras

### 1. Otimização de Hiperparâmetros

**Status:** ❌ Não implementado (usamos parâmetros fixos)

**O que fazer:**
- Implementar Grid Search ou Random Search para `max_depth`, `min_samples_leaf`
- Considerar Optuna para otimização Bayesiana
- **Restrição P4:** max_depth deve ser ≤ 8 (pipeline stages)

```python
# Exemplo de implementação futura
from sklearn.model_selection import GridSearchCV

param_grid = {
    'max_depth': [3, 4, 5, 6],
    'min_samples_leaf': [50, 100, 200],
}
```

### 2. Tratamento de Desbalanceamento de Classes

**Status:** ❌ Não implementado

**O que fazer:**
- Adicionar `class_weight='balanced'` no DecisionTreeClassifier
- Implementar SMOTE/ADASYN na preparação de dados
- Comparar performance com/sem balanceamento

```python
# Opção simples
dt = DecisionTreeClassifier(
    max_depth=5,
    class_weight='balanced',  # Adicionar isso
    random_state=42
)
```

### 3. Classificação Multi-classe (Tipo de Ataque)

**Status:** ❌ Apenas binário (Normal/Attack)

**O que fazer:**
- Adicionar suporte para `attack_cat` como target
- Gerar métricas por tipo de ataque
- Análise de quais ataques são mais difíceis de detectar

**Tipos de ataque no UNSW-NB15:**
- Fuzzers, Analysis, Backdoors, DoS, Exploits
- Generic, Reconnaissance, Shellcode, Worms

### 4. Features Adicionais para P4

**Status:** Parcial (5 features básicas)

**Features atuais:**
- `sttl` - Source TTL
- `sport` - Source Port
- `dsport` - Destination Port
- `sbytes` - Source Bytes
- `dbytes` - Destination Bytes

**Features a adicionar:**
- `proto` - Protocol (TCP/UDP/ICMP)
- `srcip_first_octet` - Primeiro octeto do IP origem
- `dstip_first_octet` - Primeiro octeto do IP destino

**Referência:** Feature extraction em `src/config.py`

### 5. Métricas Detalhadas por Classe

**Status:** ❌ Apenas accuracy/F1 geral

**O que fazer:**
- Implementar `classification_report` por tipo de ataque
- Matriz de confusão detalhada
- Análise de Falsos Negativos (ataques não detectados)

```python
from sklearn.metrics import classification_report, confusion_matrix

print(classification_report(y_test, y_pred))
cm = confusion_matrix(y_test, y_pred)
```

### 6. Threshold Tuning

**Status:** ❌ Não implementado (threshold fixo = 0.5)

**O que fazer:**
- Permitir ajuste do threshold de classificação
- Curva ROC/AUC para escolher threshold ótimo
- Trade-off: FP vs FN baseado no contexto de segurança

---

## 📊 Comparação: ML Tradicional vs Planter

| Aspecto | ML Tradicional | Planter/P4 |
|---------|----------------|------------|
| Modelos | XGBoost, DL, Ensembles | Decision Tree |
| Features | 30-50 | 5-10 |
| Latência | ms-s | μs (line-rate) |
| Accuracy | ~95-99% | ~85-92% |
| Deployment | Servidor | Switch (data plane) |

**Trade-off:** Sacrificamos um pouco de accuracy por inferência em tempo real no data plane.

---

## 📝 Referências

- [Planter Paper](https://dl.acm.org/doi/10.1145/3452296.3472934) - Metodologia original (SIGCOMM'21)
- [FLIP4](https://github.com/In-Network-Machine-Learning/FLIP4) - Federated Learning + Planter
- [UNSW-NB15](https://research.unsw.edu.au/projects/unsw-nb15-dataset) - Dataset

---

## ✅ Checklist para Implementação

- [ ] Adicionar `class_weight='balanced'`
- [ ] Suporte para classificação multi-classe
- [ ] Adicionar feature `proto` (protocol)
- [ ] Grid Search para hiperparâmetros (respeitando limite P4)
- [ ] Classification report por tipo de ataque
- [ ] Documentar accuracy por tipo de ataque
- [ ] Comparar com baseline do CyberSecurityPreprocessor
