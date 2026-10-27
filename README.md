# Cloud-Independent DevSecOps CI/CD Pipeline

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Terraform](https://img.shields.io/badge/IaC-Terraform-blue)
![Security Scan](https://img.shields.io/badge/Security-Checkov%20%2F%20TFLint-orange)
![License](https://img.shields.io/badge/License-MIT-green)

An automated, shift-left DevSecOps CI/CD security gate for Infrastructure as Code (IaC) powered by GitHub Actions. This project validates, lints, and scans Terraform code for security vulnerabilities at the Pull Request layer before code reaches production—completely free of cloud provider billing dependencies.

---

## Architecture & Workflow

[ Code Commit / PR ]
│
▼
[ GitHub Actions Runner ]
├── 1. Terraform Init (-backend=false)
├── 2. Terraform Validate (Syntax check)
├── 3. TFLint (Code quality & best practices)
└── 4. Checkov (Static Application Security Testing - SAST)
│
▼
[ Automated Security Gate Pass/Fail ] ──► [ Merge to Main ]

---

## Key Features

* **Shift-Left Security Gate:** Automated security analysis triggered on every Pull Request to catch misconfigurations prior to deployment.
* **Static Application Security Testing (SAST):** Uses **Checkov** to audit Terraform resources against enterprise security standards.
* **Code Quality & Linting:** Employs **TFLint** and `terraform validate` to enforce syntax precision and clean infrastructure code.
* **Cloud-Independent Execution:** Uses backend-free initialization (`terraform init -backend=false`) allowing the entire pipeline to execute inside GitHub Actions without requiring active cloud provider credentials or SaaS subscriptions.

---

## Automated Security Checks

| Step | Tool | Purpose | Status |
| :--- | :--- | :--- | :--- |
| **Syntax Check** | `terraform validate` | Ensures configuration files are syntactically valid | Automated |
| **IaC Linting** | `TFLint` | Checks for deprecated syntax and provider-specific errors | Automated |
| **Security Audit** | `Checkov` | Scans for IAM flaws, unencrypted storage, and permissive security groups | Automated |

---

## Pipeline Configuration

The workflow is managed via `.github/workflows/terraform.yml`:

```yaml
name: Terraform Security & Quality Pipeline

on:
  pull_request:
    branches: [ main ]
  push:
    branches: [ main ]

jobs:
  validate-and-scan:
    name: Lint, Validate & Security Scan
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.5.0
      - run: terraform init -backend=false
      - run: terraform validate
      - uses: terraform-linters/setup-tflint@v4
      - run: tflint -f compact
      - uses: bridgecrewio/checkov-action@master
        with:
          framework: terraform
          output_format: cli
          soft_fail: false

Local Usage & Testing

To run these checks locally before pushing code:

    Initialize Terraform locally (without remote backend):

terraform init -backend=false

Validate configuration syntax:

terraform validate

Run TFLint:

tflint

Run Checkov static security analysis:

checkov -d .

License

Distributed under the MIT License. See LICENSE for more information.


