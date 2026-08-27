###############################################################################
# CoreDNS rewrite: self-referencing OneUptime API calls
###############################################################################
# OneUptime's server-side rendering makes self-referential API calls back to
# itself (e.g. status page/project data for the index page) using the public
# `host` configured in helm/values.yaml (LZA's perimeter hostname). But this
# platform's VPC has no Internet Gateway (see docs/deploy-aws.md), so pods
# have no route to the public internet at all — a pod trying to connect back
# out to its own public hostname just hangs until it times out
# (ETIMEDOUT), breaking server-side rendering.
#
# Fix: rewrite in-cluster DNS lookups for that public hostname straight to
# the OneUptime nginx Service's cluster-internal DNS name, so the
# self-referential calls resolve and connect entirely inside the VPC and
# never try to leave it. This only affects DNS resolution *inside* the
# cluster — browsers still resolve/reach the real public hostname via LZA's
# perimeter ALB as before.
#
# This patches the `coredns` EKS add-on's ConfigMap directly. Corefile
# content below is the default EKS coredns add-on Corefile plus one added
# `rewrite name exact` line — if you customize the coredns add-on itself
# (e.g. via `cluster_addons.coredns.configuration_values` in main.tf), keep
# this in sync.
resource "kubernetes_config_map_v1_data" "coredns_rewrite" {
  metadata {
    name      = "coredns"
    namespace = "kube-system"
  }

  data = {
    Corefile = <<-EOF
      .:53 {
          errors
          health {
            lameduck 5s
          }
          ready
          rewrite name exact ${var.oneuptime_public_host} my-oneuptime-nginx.default.svc.cluster.local
          kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
            ttl 30
          }
          prometheus :9153
          forward . /etc/resolv.conf
          cache 30
          loop
          reload
          loadbalance
      }
    EOF
  }

  force = true

  depends_on = [module.eks]
}

# CoreDNS doesn't hot-reload the Corefile on ConfigMap changes — the
# `reload` plugin above only picks it up on its own polling interval
# (~30-45s with jitter, and only if kubectl/aws-cli are configured against
# this cluster when `terraform apply` runs). Force an immediate rollout so
# the rewrite rule takes effect right away instead of waiting on that poll.
resource "null_resource" "coredns_restart" {
  triggers = {
    corefile = kubernetes_config_map_v1_data.coredns_rewrite.data["Corefile"]
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name} && kubectl rollout restart deployment/coredns -n kube-system"
  }

  depends_on = [kubernetes_config_map_v1_data.coredns_rewrite]
}
