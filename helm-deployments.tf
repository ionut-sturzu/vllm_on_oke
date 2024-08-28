# Copyright (c) 2024 Oracle Corporation and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

locals {
  deploy_from_operator = var.create_operator_and_bastion
  deploy_from_local    = alltrue([!local.deploy_from_operator, var.control_plane_is_public])
}

data "oci_containerengine_cluster_kube_config" "kube_config" {
  count = local.deploy_from_local ? 1 : 0

  cluster_id = module.oke.cluster_id
  endpoint   = "PUBLIC_ENDPOINT"
}

module "nginx" {
  count  = var.deploy_nginx ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.bastion_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deploy_from_operator = local.deploy_from_operator
  deploy_from_local    = local.deploy_from_local

  deployment_name     = "ingress-nginx"
  helm_chart_name     = "ingress-nginx"
  namespace           = "nginx"
  helm_repository_url = "https://kubernetes.github.io/ingress-nginx"

  pre_deployment_commands  = []
  post_deployment_commands = []

  helm_template_values_override = templatefile(
    "${path.root}/helm-values-templates/nginx-values.yaml.tpl",
    {
      min_bw        = 100,
      max_bw        = 100,
      pub_lb_nsg_id = module.oke.pub_lb_nsg_id
      state_id      = local.state_id
    }
  )
  helm_user_values_override = try(base64decode(var.nginx_user_values_override), var.nginx_user_values_override)

  kube_config = one(data.oci_containerengine_cluster_kube_config.kube_config.*.content)
  depends_on  = [module.oke]
}


module "cert-manager" {
  count  = var.deploy_cert_manager ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.bastion_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deploy_from_operator = local.deploy_from_operator
  deploy_from_local    = local.deploy_from_local

  deployment_name     = "cert-manager"
  helm_chart_name     = "cert-manager"
  namespace           = "cert-manager"
  helm_repository_url = "https://charts.jetstack.io"

  pre_deployment_commands = []
  post_deployment_commands = [
    "cat <<'EOF' | kubectl apply -f -",
    "apiVersion: cert-manager.io/v1",
    "kind: ClusterIssuer",
    "metadata:",
    "  name: le-clusterissuer",
    "spec:",
    "  acme:",
    "    # You must replace this email address with your own.",
    "    # Let's Encrypt will use this to contact you about expiring",
    "    # certificates, and issues related to your account.",
    "    email: user@oracle.om",
    "    server: https://acme-staging-v02.api.letsencrypt.org/directory",
    "    privateKeySecretRef:",
    "      # Secret resource that will be used to store the account's private key.",
    "      name: le-clusterissuer-secret",
    "    # Add a single challenge solver, HTTP01 using nginx",
    "    solvers:",
    "    - http01:",
    "        ingress:",
    "          ingressClassName: nginx",
    "EOF"
  ]

  helm_template_values_override = templatefile(
    "${path.root}/helm-values-templates/cert-manager-values.yaml.tpl",
    {}
  )
  helm_user_values_override = try(base64decode(var.cert_manager_user_values_override), var.cert_manager_user_values_override)

  kube_config = one(data.oci_containerengine_cluster_kube_config.kube_config.*.content)

  depends_on = [module.oke]
}


module "qdrant" {
  count  = var.deploy_qdrant ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.bastion_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deploy_from_operator = local.deploy_from_operator
  deploy_from_local    = local.deploy_from_local

  deployment_name     = "qdrant"
  helm_chart_name     = "qdrant"
  namespace           = "default"
  helm_repository_url = "https://qdrant.to/helm"

  pre_deployment_commands  = []
  post_deployment_commands = []

  helm_template_values_override = templatefile(
    "${path.root}/helm-values-templates/qdrant-values.yaml.tpl",
    {}
  )
  helm_user_values_override = try(base64decode(var.qdrant_user_values_override), var.qdrant_user_values_override)

  kube_config = one(data.oci_containerengine_cluster_kube_config.kube_config.*.content)

  depends_on = [module.oke]
}


module "jupyterhub" {
  count  = var.deploy_jupyterhub ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.bastion_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deploy_from_operator = local.deploy_from_operator
  deploy_from_local    = local.deploy_from_local

  deployment_name     = "jupyterhub"
  helm_chart_name     = "jupyterhub"
  namespace           = "default"
  helm_repository_url = "https://hub.jupyter.org/helm-chart/"

  pre_deployment_commands = ["export PUBLIC_IP=$(kubectl get svc -A -l app.kubernetes.io/name=ingress-nginx  -o json | jq -r '.items[] | select(.spec.type == \"LoadBalancer\") | .status.loadBalancer.ingress[].ip')"]
  deployment_extra_args = [
    "--set ingress.hosts[0]=jupyter.$${PUBLIC_IP}.nip.io",
    "--set ingress.tls[0].hosts[0]=jupyter.$${PUBLIC_IP}.nip.io",
    "--set ingress.tls[0].secretName=jupyter-tls"
  ]
  post_deployment_commands = []

  helm_template_values_override = templatefile(
    "${path.root}/helm-values-templates/jupyterhub-values.yaml.tpl",
    {
      admin_user     = var.jupyter_admin_user
      admin_password = var.jupyter_admin_password
      playbooks_repo = var.jupyter_playbooks_repo
    }
  )
  helm_user_values_override = try(base64decode(var.jupyterhub_user_values_override), var.jupyterhub_user_values_override)

  kube_config = one(data.oci_containerengine_cluster_kube_config.kube_config.*.content)

  depends_on = [module.oke, module.nginx]
}

module "vllm" {
  count  = var.deploy_vllm ? 1 : 0
  source = "./helm-module"

  bastion_host    = module.oke.bastion_public_ip
  bastion_user    = var.bastion_user
  operator_host   = module.oke.operator_private_ip
  operator_user   = var.bastion_user
  ssh_private_key = tls_private_key.stack_key.private_key_openssh

  deploy_from_operator = local.deploy_from_operator
  deploy_from_local    = local.deploy_from_local

  deployment_name     = "llm"
  helm_chart_name     = "vllm"
  namespace           = "default"
  helm_repository_url = "https://robo-cap.github.io/helm-charts/"

  pre_deployment_commands = ["export PUBLIC_IP=$(kubectl get svc -A -l app.kubernetes.io/name=ingress-nginx  -o json | jq -r '.items[] | select(.spec.type == \"LoadBalancer\") | .status.loadBalancer.ingress[].ip')"]
  deployment_extra_args = [
    "--set ingress.hosts[0]=llm.$${PUBLIC_IP}.nip.io",
    "--set ingress.tls[0].hosts[0]=llm.$${PUBLIC_IP}.nip.io",
    "--set ingress.tls[0].secretName=llm-tls"
  ]
  post_deployment_commands = []

  helm_template_values_override = templatefile(
    "${path.root}/helm-values-templates/vllm-values.yaml.tpl",
    {
      HF_TOKEN      = var.HF_TOKEN
      LLM_API_KEY   = var.LLM_API_KEY
      model         = var.model
      max_model_len = tostring(var.max_model_len)
    }
  )
  helm_user_values_override = try(base64decode(var.vllm_user_values_override), var.vllm_user_values_override)

  kube_config = one(data.oci_containerengine_cluster_kube_config.kube_config.*.content)

  depends_on = [module.oke, module.nginx]
}