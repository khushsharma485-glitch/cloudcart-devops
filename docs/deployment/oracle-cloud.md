# Deploying CloudCart on Oracle Cloud Always Free ($0)

CloudCart runs on one **Always Free** Ampere A1 server (arm64, 2 OCPU,
12 GB RAM, 100 GB disk) with **k3s**, a lightweight, CNCF-conformant
Kubernetes. Argo CD deploys the same Helm chart, Argo Rollouts, monitoring
and logging as on AWS, from this GitHub repository.

```
GitHub push -> CI (tests, Trivy) -> multi-arch image -> ghcr.io (free)
            -> CI bumps helm/cloudcart/values-oci.yaml
Argo CD on the Oracle server pulls Git -> k3s -> http://<public-ip>/api/...
```

| Free resource used | Always Free limit |
|---|---|
| VM.Standard.A1.Flex, 2 OCPU / 12 GB | 2 OCPU / 12 GB in total (since 2026-06-15) |
| 100 GB boot volume | 200 GB block storage in total |
| VCN, internet gateway, public IP, security list | free |
| Container images on GitHub Container Registry | free for public packages |

Not used, because they are **not** Always Free: OKE (managed Kubernetes),
NAT gateway, and a second load balancer. Terraform validations stop you from
sizing the server above the free limits.

## 1. One-time setup in the OCI console

1. Sign up at https://signup.cloud.oracle.com and choose a **home region**
   close to you. Always Free resources exist only in the home region.
2. **Create an API key for Terraform:** Profile (top right) -> *My profile* ->
   *API keys* -> *Add API key* -> *Generate API key pair* ->
   **Download private key** -> *Add*. Then copy the "Configuration file preview".
3. On your PC, save the private key as `C:\Users\<you>\.oci\oci_api_key.pem` and
   the preview text as `C:\Users\<you>\.oci\config`. Change its `key_file=`
   line to that path. These files stay on your machine; never commit them.
4. You need an SSH key: `ssh-keygen -t ed25519` (press Enter for the defaults).

## 2. Create the server

```bash
cd terraform/oci
cp terraform.tfvars.example terraform.tfvars    # region, tenancy_ocid, your IP
terraform init
terraform apply                                 # about 2 minutes
```

If you get **"Out of host capacity"**, Oracle has no free A1 capacity in that
availability domain right now. Set `availability_domain_index = 1` (or 2), or
retry later.

## 3. Hand it over to GitOps

```bash
scripts/oci/bootstrap.sh $(terraform -chdir=terraform/oci output -raw public_ip)
```

The script waits for k3s, opens an SSH tunnel to the Kubernetes API (the API
is never exposed to the Internet), installs Argo CD, creates random passwords
on the cluster, and applies `argocd/environments/root-oci.yaml`. From then on:

- every push to `main` -> CI publishes images -> Argo CD deploys them;
- `BASE_URL=http://<public-ip> HEALTH_URLS="" tests/smoke/smoke-test.sh` checks it;
- `scripts/oci/bootstrap.sh <ip> tunnel` re-opens the tunnel for kubectl.

## Notes

- **Images are public**: packages pushed by this public repository's CI inherit
  its visibility, so k3s pulls them without credentials (verified with an
  anonymous pull of all three images).
- **Idle reclamation:** Oracle may reclaim Always Free compute that stays
  almost idle for 7 days. CloudCart with monitoring normally keeps the server
  busy enough; if it is reclaimed, `terraform apply` + bootstrap rebuild it.
- **Chaos endpoints are disabled** here (`values-oci.yaml`), because the API
  is public.
- **Tear down:** `terraform -chdir=terraform/oci destroy`.
