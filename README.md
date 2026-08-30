# hello-spring-boot-eks

`hello-spring-boot`（ECS/Fargate 版）を **EKS** に載せ替えた学習用リポジトリ。
アプリは同じ Spring Boot (Kotlin) + jOOQ + Flyway + Aurora MySQL。インフラだけを
EKS 向けに書き直しています。

まずは **認知負荷の低い Fargate 構成**で「Pod が動いて ALB 経由で外から見える」所まで
到達し、慣れたら EC2 マネージドノードグループへ発展させる方針です。

## ECS 版との対応

| 役割 | ECS 版 (`hello-spring-boot`) | EKS 版 (このリポジトリ) |
|---|---|---|
| コンテナ実行 | ECS Service (Fargate) | Deployment on **EKS Fargate** |
| ネットワーク公開 | ALB + Target Group (Terraform) | **Ingress** + AWS Load Balancer Controller が ALB を自動生成 |
| 権限 | ECS Task Execution Role | **IRSA**（ServiceAccount ↔ IAM Role） |
| シークレット | ECS secrets → Secrets Manager | Secrets Manager → `kubectl` で K8s Secret 化（後で External Secrets へ発展可） |
| DB | Aurora Serverless v2 | 同じ（流用） |
| ネットワーク基盤 | VPC/subnet/NAT/ECR | 同じ（subnet に EKS 用タグを追加） |

## 構成

```
infra/
  platform/aws/      # VPC, subnet(EKS用タグ), NAT, IGW, ECR   → tfstate key: aws/platform
  application/aws/    # EKS, Fargate, OIDC/IRSA, Aurora, Secrets → tfstate key: aws/application
k8s/                 # 素の kubectl マニフェスト (Namespace/Deployment/Service/Ingress)
scripts/             # build-and-push / deploy / teardown
```

Terraform は **AWS リソースのみ**を管理します。CoreDNS のパッチ・ALB Controller の
導入・Secret 作成・`kubectl apply` といった**クラスタ内の操作は `scripts/deploy.sh`**
に集約し、コマンドが1つずつ目に見えるようにしています（学習用の意図）。

## 前提ツール

- Terraform, AWS CLI v2, `kubectl`, `helm`, `jq`, Docker
- 検証用 AWS アカウント **SANDBOX-EKS**（`aws-root-account-config` で作成）への
  SSO プロファイル。以降 `AWS_PROFILE=sandbox-eks` を前提に記載します。

## 手順

### 0. ブートストラップ（初回のみ）

tfstate 用 S3 バケットを先に作成します（backend はバケットを自動生成しないため）。

```bash
aws s3 mb s3://hello-spring-boot-eks-tfstate --region ap-northeast-1
```

### 1. platform 層（VPC/ECR）

```bash
cd infra/platform/aws
terraform init
terraform apply
```

### 2. application 層（EKS/Aurora/IRSA）

```bash
cd ../../application/aws
terraform init
terraform apply     # EKS 作成に 10〜15 分ほどかかります
```

### 3. イメージを ECR へ push

```bash
cd ../../..           # リポジトリルート
AWS_PROFILE=sandbox-eks ./scripts/build-and-push.sh latest
```

### 4. デプロイ（クラスタ設定 + アプリ）

```bash
AWS_PROFILE=sandbox-eks ./scripts/deploy.sh latest
```

`deploy.sh` の中身:
1. `aws eks update-kubeconfig`
2. **CoreDNS を Fargate 対応に**（`eks.amazonaws.com/compute-type=ec2` annotation を除去して再起動）
3. **AWS Load Balancer Controller** を Helm で導入（IRSA ロールを ServiceAccount に紐付け）
4. Namespace 作成 + Secrets Manager から **K8s Secret `db`** を生成
5. `k8s/` を `kubectl apply`（image は ECR URL に置換）
6. Ingress が払い出す **ALB の URL** を表示

最後に出る `http://<alb>/` にアクセスして `Hello World!` が返れば成功です。

### 5. 後片付け

```bash
AWS_PROFILE=sandbox-eks ./scripts/teardown.sh
```

Ingress（= ALB）を先に削除してから `terraform destroy` する順序になっています。
ALB を残したまま VPC を消そうとすると失敗するためです。

## つまづきポイント（Fargate 特有）

- **CoreDNS**: 既定で EC2 前提。パッチしないと Pod が Pending のまま → 名前解決不能。
  `deploy.sh` のステップ2で対応。
- **ALB は IP ターゲット必須**: Fargate に NodePort は無いので `target-type: ip`
  （`k8s/ingress.yaml` に設定済み）。
- **subnet タグ**: `kubernetes.io/role/elb`（public）/`internal-elb`（private）が無いと
  Controller が subnet を発見できない（platform 層で付与済み）。
- **DaemonSet / hostPath / 特権コンテナは不可**（今回は不要）。

## スキーマを変更したら（jOOQ 再生成）

生成済みコードは `src/main/generated` にコミット済みなので通常ビルドに DB は不要です。
スキーマを変えたときだけローカル MySQL を使って再生成します。

```bash
docker compose up -d
./gradlew flywayMigrate
./gradlew generateHellodbJooq
```

## 次の学習ステップ

1. **EC2 マネージドノードグループ**に載せ替え（ノード/kubelet/DaemonSet/オートスケール）
2. **External Secrets Operator / Secrets Store CSI** で Secret を宣言的に
3. **HPA**（オートスケール）と **liveness/readiness** の作り込み（Actuator 導入）
4. コンテナログの集約（Fargate logging → CloudWatch）
5. マニフェストの **Helm / Kustomize** 化、CI/CD（GitHub Actions）
```
