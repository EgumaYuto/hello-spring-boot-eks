# local — kind でローカル学習（AWS費用ゼロ）

同じ Spring Boot アプリを、**AWS を一切使わず**ローカルの Kubernetes（[kind](https://kind.sigs.k8s.io/)）で動かす環境です。
普段の学習はここで行い、AWS 固有の機能（IRSA / ALB Controller / Fargate）を試すときだけ EKS を立てる、という使い分けを想定しています。

Kubernetes の核心（Deployment / Service / Ingress / Secret / probe / initContainer / kubectl / rollout）は
クラウドと**同じ動き**なので、8割はここで学べます。

## EKS版との違い（エッジだけ差し替え）

| | EKS版 (`k8s/`) | ローカル版 (`local/manifests/`) |
|---|---|---|
| 公開 | ALB Ingress + LB Controller | **nginx Ingress**（`http://localhost/`） |
| DB | Aurora Serverless v2 | **クラスタ内 MySQL Pod**（emptyDir） |
| Secret | Secrets Manager → deploy.sh | **静的な Secret**（docker-compose と同値） |
| イメージ | ECR に push | **`kind load` でクラスタに直接**投入 |
| 費用 | 時間課金 | **無料** |

中央の Deployment / Service / probe / Flyway 起動などは EKS版と同じです。

## 前提ツール

```bash
brew install kind kubectl        # Docker Desktop などの docker も必要
```
AWS 認証情報は不要です。

## 使い方

```bash
# 起動（kind作成 → nginx導入 → イメージビルド&投入 → デプロイ）
./local/up.sh

# 動作確認
curl http://localhost/           # => Hello World!
kubectl get pods -n hello-spring-boot
kubectl logs -n hello-spring-boot deploy/hello-spring-boot -f

# 片付け（クラスタごと削除）
./local/down.sh
```

## しくみ（起動の流れ）

1. `kind create cluster` … Docker コンテナ1つが Kubernetes ノードになる。ホストの 80/443 をノードにマップ
2. nginx Ingress controller を導入 → `http://localhost/` で受ける
3. `./gradlew bootJar`（jOOQ はコミット済みソースを使い DB 不要）→ `docker build` → `kind load` でクラスタへ
4. マニフェスト適用: Namespace / Secret / MySQL / アプリ(Deployment+Service) / Ingress
5. アプリの `initContainer` が MySQL の 3306 を待ってから起動 → Flyway が起動時に `V1__create_users_table.sql` を適用

## 触ってみる学習ネタ

- `kubectl scale deploy/hello-spring-boot -n hello-spring-boot --replicas=3` → Pod が増える様子
- `kubectl describe ingress -n hello-spring-boot` → ルーティングの確認
- `kubectl get events -n hello-spring-boot` → スケジューリング/起動の流れ
- MySQL を **StatefulSet + PVC** に変えて永続化（`emptyDir` からの発展課題）
- `kubectl delete pod` でアプリ Pod を消して自己回復を観察

## 注意

- MySQL は `emptyDir` なので Pod が再起動するとデータは消えます（Flyway が再作成するので学習には問題なし）。
- ポート 80 を使うので、ローカルで 80 を使う別プロセスがあると衝突します。
