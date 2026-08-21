output "cluster_name" {
  description = "Name of the created EKS cluster."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Kubernetes API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_region" {
  description = "AWS region the cluster was created in."
  value       = var.aws_region
}

output "configure_kubectl" {
  description = "Command to configure kubectl to talk to the new cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "vpc_id" {
  description = "VPC ID housing the cluster (platform-managed, looked up by var.vpc_name)."
  value       = data.aws_vpc.selected.id
}

output "subnet_ids" {
  description = "IDs of the two platform-managed subnets (looked up by var.subnet_a/var.subnet_b), used for both the EKS cluster and the Network Load Balancer. Copy these into helm/values.yaml's service.beta.kubernetes.io/aws-load-balancer-subnets annotation."
  value       = [data.aws_subnet.a.id, data.aws_subnet.b.id]
}
