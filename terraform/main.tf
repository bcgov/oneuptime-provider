###############################################################################
# Networking
###############################################################################
# The VPC and subnets are platform-managed and cannot be created, modified,
# or tagged by users — no `aws_vpc`/`aws_subnet` *resources* here. The
# cluster is deployed into the existing VPC/subnets, looked up by Name tag
# in data.tf (var.vpc_name / var.subnet_a / var.subnet_b). Because we can't
# tag these subnets for kubernetes.io/role/elb auto-discovery, the Network
# Load Balancer's subnets are instead specified explicitly via a Service
# annotation in helm/values.yaml (service.beta.kubernetes.io/aws-load-balancer-subnets).

###############################################################################
# EKS cluster
###############################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id                   = data.aws_vpc.selected.id
  subnet_ids               = [data.aws_subnet.a.id, data.aws_subnet.b.id]
  control_plane_subnet_ids = [data.aws_subnet.a.id, data.aws_subnet.b.id]

  cluster_endpoint_public_access = true

  # No OIDC-based IRSA — creating an OIDC identity provider
  # (iam:CreateOpenIDConnectProvider) is an account-wide IAM action typically
  # blocked on this platform. EKS Pod Identity (below) is used instead to
  # grant the EBS CSI driver its IAM role, which only needs
  # iam:CreateRole/AttachRolePolicy plus eks:CreatePodIdentityAssociation.
  enable_irsa = false

  # Managed add-ons. The EBS CSI driver is required so PostgreSQL, Redis and
  # ClickHouse (all built on PVCs) can provision EBS-backed volumes. The
  # eks-pod-identity-agent add-on is required for the Pod Identity
  # association (below) to actually inject credentials into the CSI driver's
  # pods.
  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    eks-pod-identity-agent = {
      most_recent = true
    }
    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    default = {
      # EKS 1.30+ no longer supports the AL2 AMI family for managed node
      # groups (default before this module version); AL2023 is required.
      ami_type = "AL2023_x86_64_STANDARD"

      min_size       = var.node_group_min_size
      max_size       = var.node_group_max_size
      desired_size   = var.node_group_desired_size
      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      labels = {
        role = "oneuptime"
      }
    }
  }

  # Grant the identity running terraform cluster-admin so it can immediately
  # helm install after apply.
  enable_cluster_creator_admin_permissions = true

  tags = var.tags
}

###############################################################################
# EKS Pod Identity role for the EBS CSI driver add-on
###############################################################################
# Plain IAM role trusted by the Pod Identity service (no OIDC provider
# needed) + an association binding it to the CSI driver's ServiceAccount.

data "aws_iam_policy_document" "ebs_csi_pod_identity_assume_role" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi_driver" {
  name               = "${var.cluster_name}-ebs-csi-driver"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_pod_identity_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi_driver" {
  role       = aws_iam_role.ebs_csi_driver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_pod_identity_association" "ebs_csi_driver" {
  cluster_name    = module.eks.cluster_name
  namespace       = "kube-system"
  service_account = "ebs-csi-controller-sa"
  role_arn        = aws_iam_role.ebs_csi_driver.arn
}
