# ugallin – Python app on AWS EKS, built with Terraform and GitHub Actions

A very basic Python web app, packaged with Docker, running on a Kubernetes (EKS) cluster
in its own VPC, reachable from the internet through a load balancer. Everything is created
with Terraform and deployed automatically by a GitHub Actions pipeline.
Every AWS resource name starts with the project name **`ugallin`** (Terraform variable `projectname`).

```
                    Internet
                       │  http://<NLB DNS name>  (port 80)
                       ▼
┌──────────────────── VPC 10.0.0.0/16 (ugallin-vpc) ──────────────────────┐
│  public subnet (AZ a)               public subnet (AZ b)                │
│  ┌─────────────┐ ┌─────────────┐                                        │
│  │ NAT Gateway │ │  ugallin-nlb (Network Load Balancer) ─────────┐       │
│  └──────┬──────┘ └───────────────────────────────────────────────│───────│
│         │ outbound only                                    port 30080    │
│  private subnet (AZ a)               private subnet (AZ b)       ▼       │
│  ┌──────────────────────┐           ┌──────────────────────┐            │
│  │ worker node          │           │ worker node          │            │
│  │  └ pod ugallin-app   │           │  └ pod ugallin-app   │ port 8080  │
│  └──────────────────────┘           └──────────────────────┘            │
│               EKS control plane "ugallin" (managed by AWS)               │
└──────────────────────────────────────────────────────────────────────────┘
```

## What is where

| Path | What it does | Task step |
|---|---|---|
| `terraform/bootstrap/` | One-time setup: S3 bucket for the Terraform state + IAM role for GitHub Actions | – |
| `terraform/infra/network.tf` | VPC, 2 public + 2 private subnets in 2 AZs, Internet Gateway, NAT Gateway, route tables, network ACLs | 1–6 |
| `terraform/infra/security.tf` | Security groups for the control plane, the worker nodes and the load balancer | 7 |
| `terraform/infra/iam.tf` | IAM roles for the EKS cluster and the worker nodes | 8 |
| `terraform/infra/eks.tf` | EKS cluster, worker nodes, cluster admins | – |
| `terraform/infra/ecr.tf` | ECR repository for the Docker image | – |
| `terraform/infra/loadbalancer.tf` | Network Load Balancer that makes the app reachable from the internet | 12 |
| `terraform/infra/variables.tf` | Settings, including `projectname = "ugallin"` | 14 |
| `app/app.py`, `app/test_app.py` | The Python app (standard library only) and its unit test | 9 |
| `app/Dockerfile` | Packages the app into a Docker image | 10 |
| `k8s/app.yaml` | Kubernetes Deployment (2 pods) + NodePort Service | 11 |
| `.github/workflows/deploy.yml` | Pipeline: `terraform plan` on pull requests, `terraform apply` + deploy on push to main | 13 |

## Cost – remember to remove everything when done!

While the infrastructure exists, AWS bills about **$0.25/hour (~$6/day)**: EKS control plane
~$0.10/h, NAT Gateway ~$0.045/h, 2 × t3.small ~$0.05/h, load balancer ~$0.025/h, plus traffic.

## Prerequisites

- AWS CLI, logged in to the account (`aws sts get-caller-identity` works)
- Terraform ≥ 1.10, kubectl, Docker, git
- An **empty GitHub repository named `ugallin`** under your user (`UJoe`).
  Other name or owner? Pass `-var github_repo=<name> -var github_owner=<owner>` in step 1.

## Installation

### 1. Bootstrap (once, by hand, ~1 minute)

Creates the S3 bucket for the Terraform state and the IAM role the pipeline logs in with.

```bash
cd terraform/bootstrap
terraform init
terraform apply          # review the plan (5 resources), type "yes"
```

Note the two outputs: `tfstate_bucket` and `github_actions_role_arn`.
Keep `terraform/bootstrap/terraform.tfstate` – it is needed to remove these resources later.

### 2. GitHub settings

In the GitHub repository → **Settings → Secrets and variables → Actions**:

| Type | Name | Value |
|---|---|---|
| Secret | `AWS_ROLE_ARN` | the `github_actions_role_arn` output, e.g. `arn:aws:iam::362099375729:role/ugallin-github-actions` |
| Variable | `ADMIN_PRINCIPAL_ARN` | the output of `aws sts get-caller-identity --query Arn --output text` (gives *you* kubectl access) |

### 3. Push the code – the pipeline builds everything (~20 minutes the first time)

```bash
cd ../..                 # back to the project root (codecool/allin)
git init -b main
git add .
git commit -m "Initial infrastructure and app"
git remote add origin https://github.com/UJoe/ugallin.git
git push -u origin main
```

Watch it in the repository's **Actions** tab. The run goes through:
`test` → `terraform` (apply: VPC, EKS, NLB, … ~15 min) → `deploy` (build image, push to ECR, `kubectl apply`).
The app URL is printed at the end of the run (and in its summary).

### 4. Check that it works

```bash
# Connect kubectl to the new cluster
aws eks update-kubeconfig --region eu-central-1 --name ugallin

kubectl get nodes                          # 2 nodes, STATUS Ready
kubectl get pods -l app=ugallin-app        # 2 pods, STATUS Running

# Get the URL and call the app (the load balancer needs 1–3 minutes to become healthy)
URL=http://$(aws elbv2 describe-load-balancers --names ugallin-nlb --query 'LoadBalancers[0].DNSName' --output text)
curl $URL            # Hello from ugallin! Served by: ugallin-app-xxxxx
```

Run `curl` a few times: the pod name changes, because the load balancer spreads the requests.

### Making changes later

- Open a **pull request** to `main` → the pipeline runs the tests and `terraform plan`, so you can
  review what would change. Nothing is changed.
- **Merge** it → the pipeline runs `terraform apply`, builds a new image (tagged with the commit SHA)
  and rolls it out to Kubernetes.

### Without the pipeline (optional, everything from your laptop)

```bash
# Infrastructure (after step 1)
cd terraform/infra
export TF_VAR_admin_principal_arn=$(aws sts get-caller-identity --query Arn --output text)
terraform init
terraform apply

# Image
REPO=$(terraform output -raw ecr_repository_url)
aws ecr get-login-password --region eu-central-1 | docker login --username AWS --password-stdin ${REPO%%/*}
docker build -t $REPO:v1 ../../app
docker push $REPO:v1

# Kubernetes
aws eks update-kubeconfig --region eu-central-1 --name ugallin
sed "s|IMAGE_PLACEHOLDER|$REPO:v1|" ../../k8s/app.yaml | kubectl apply -f -
```

## Entering the container with bash

The image is based on `python:3.13-slim`, which includes bash.

**In Kubernetes** (after `aws eks update-kubeconfig ...` from step 4):

```bash
# Open bash in one of the app's pods (kubectl picks a pod of the Deployment)
kubectl exec -it deployment/ugallin-app -- bash

# ...or in a specific pod
kubectl get pods -l app=ugallin-app
kubectl exec -it <pod-name> -- bash
```

Inside the container you can, for example:

```bash
hostname                    # the pod name
cat app.py                  # the running code (working directory: /app)
python -c "import urllib.request; print(urllib.request.urlopen('http://localhost:8080/').read().decode())"
exit                        # leave the container (it keeps running)
```

The container runs as an unprivileged user (UID 10001) for security, so the prompt shows
`I have no name!@...` – that is expected.

**Locally with Docker** (no AWS needed):

```bash
cd app
docker build -t ugallin-app .
docker run -d --name ugallin-app -p 8080:8080 ugallin-app    # app on http://localhost:8080
docker exec -it ugallin-app bash                             # enter the container
docker rm -f ugallin-app                                     # stop and remove it
```

## Removing all resources

Remove in **reverse order**: first the infrastructure, then the bootstrap resources
(the infrastructure's state is stored in the bootstrap bucket).

```bash
# 1. Infrastructure: EKS, nodes, load balancer, NAT, VPC, ECR (with images) ... (~15 min)
cd terraform/infra
export TF_VAR_admin_principal_arn=$(aws sts get-caller-identity --query Arn --output text)
terraform init
terraform destroy        # review: ~41 resources, type "yes"

# 2. Bootstrap: state bucket + GitHub Actions role (~1 min)
cd ../bootstrap
terraform destroy        # 5 resources, type "yes"

# 3. Local leftovers (optional)
kubectl config delete-context arn:aws:eks:eu-central-1:362099375729:cluster/ugallin
docker rmi ugallin-app
```

No `kubectl delete` is needed first: the load balancer is managed by Terraform (not by
Kubernetes), and the pods disappear together with the cluster.

After step 2 the pipeline can no longer log in to AWS. Delete or archive the GitHub
repository (or disable its workflow), otherwise the next push fails – or worse, if you
recreate the bootstrap, it would build everything again.

Check that nothing is left:

```bash
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=ugallin \
  --query 'ResourceTagMappingList[].ResourceARN' --output text      # should print nothing
```

## Troubleshooting

| Problem | Cause / fix |
|---|---|
| Pipeline: `Not authorized to perform sts:AssumeRoleWithWebIdentity` | `AWS_ROLE_ARN` secret wrong, or the repo name/owner differs from the bootstrap variables `github_repo` / `github_owner`. |
| Pipeline: `admin_principal_arn must be an IAM ARN` | The GitHub variable `ADMIN_PRINCIPAL_ARN` is missing or wrong. |
| `kubectl`: `You must be logged in to the server` | Your ARN differs from `ADMIN_PRINCIPAL_ARN`; compare with `aws sts get-caller-identity`. |
| `kubectl` times out / talks to a wrong cluster | Check `kubectl config current-context`; run the `aws eks update-kubeconfig` command again. |
| `curl` to the URL hangs right after deployment | The load balancer is still running health checks; wait 1–3 minutes. |
| Pod in `ImagePullBackOff` | The image tag does not exist in ECR – check `aws ecr describe-images --repository-name ugallin-app`. |
