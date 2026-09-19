#!/bin/bash
set -euo pipefail

# =============================================================================
# Script de Bootstrap para EC2 Ubuntu Server
# Plataforma de Dados Open Source com Kubernetes (kind)
# =============================================================================

echo "=============================================="
echo "  Data Platform - EC2 Bootstrap Script"
echo "=============================================="

# Atualizar sistema
echo "[1/8] Atualizando sistema..."
sudo apt-get update && sudo apt-get upgrade -y

# Instalar dependências básicas
echo "[2/8] Instalando dependências básicas..."
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    unzip \
    jq \
    make

# Instalar Docker
echo "[3/8] Instalando Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
    sudo systemctl enable docker
    sudo systemctl start docker
    echo "Docker instalado. Você precisará fazer logout/login para usar sem sudo."
else
    echo "Docker já instalado."
fi

# Instalar kubectl
echo "[4/8] Instalando kubectl..."
if ! command -v kubectl &> /dev/null; then
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm kubectl
else
    echo "kubectl já instalado."
fi

# Instalar kind
echo "[5/8] Instalando kind..."
if ! command -v kind &> /dev/null; then
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.24.0/kind-linux-amd64
    sudo install -o root -g root -m 0755 kind /usr/local/bin/kind
    rm kind
else
    echo "kind já instalado."
fi

# Instalar Helm
echo "[6/8] Instalando Helm..."
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "Helm já instalado."
fi

# Instalar AWS CLI v2
echo "[7/8] Instalando AWS CLI v2..."
if ! command -v aws &> /dev/null; then
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
else
    echo "AWS CLI já instalado."
fi

# Instalar Terraform
echo "[8/8] Instalando Terraform..."
if ! command -v terraform &> /dev/null; then
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt-get update && sudo apt-get install -y terraform
else
    echo "Terraform já instalado."
fi

echo ""
echo "=============================================="
echo "  Instalação concluída!"
echo "=============================================="
echo ""
echo "Versões instaladas:"
echo "  Docker:    $(docker --version 2>/dev/null || echo 'requer logout/login')"
echo "  kubectl:   $(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)"
echo "  kind:      $(kind version)"
echo "  Helm:      $(helm version --short)"
echo "  AWS CLI:   $(aws --version)"
echo "  Terraform: $(terraform version | head -1)"
echo ""