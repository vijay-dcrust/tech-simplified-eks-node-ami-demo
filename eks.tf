locals {
  eks_cluster_name = "test-demo-eks-cluster-01"
}

locals {
  common_tags = {
    tag_env         = var.environment
    tag_cost_centre = var.tech_family
  }
}

module "eks" {
  source                  = "../../../../modules/aws/eks"
  subnet_ids              = data.aws_subnet_ids.k8ssubnetids.ids
  iam_eks_cluster         = join("-", ["iam", local.eks_cluster_name])
  iam_eks_node_group_name = join("-", ["iam-node", local.eks_cluster_name])
  eks_cluster_name        = local.eks_cluster_name
  endpoint_public_access  = false
  security_group_ids      = [aws_security_group.eks.id]
  eks_version             = var.eks_version
  kms_key_arn             = module.eks_master_key.kms_key_arn
  eks_kms_resources       = ["secrets"]
  install_add_on          = var.install_add_on
  tags_basic = merge(local.common_tags, {
    Name               = local.eks_cluster_name
    tag_component_name = "eks"
  })
}

locals {
  node_group = {
    test-demo-eks-cluster-nodegroup05 : {
      image_id      =   "ami-abcv2xxxx"
      desired_size  =   "14"
      max_size      = 30
      min_size      = 3
      instance_type = "c5a.xlarge"
      kubelet_extra_args = "--max-pods=110"
    }
  }
}

module "eks_node_group" {
  depends_on = [
    module.eks,
    module.eks_master_key
  ]
  for_each                = local.node_group
  source                  = "../../../../modules/aws/eks-node-group/v1"
  subnet_ids              = data.aws_subnet_ids.k8ssubnetids.ids
  eks_cluster_name        = local.eks_cluster_name
  launch_template_version = 1
  encrypted               = "true"
  kms_key_id              = module.eks_master_key.kms_key_arn

  eks_node_group_name  = each.key
  launch_template_name = join("-", [each.key, "template"])
  user_data = base64encode(templatefile("${path.module}/eks-cluster-mng.sh", { API_SERVER_URL = module.eks.endpoint,
    B64_CLUSTER_CA = module.eks.kubeconfig_certificate_authority_data,
    CLUSTER_NAME   = local.eks_cluster_name,
    NODE_GROUP     = each.key,
    AMI_ID         = each.value.image_id,
    kubelet_extra_args  = each.value.kubelet_extra_args
  }))
  iam_eks_node_group_arn = module.eks.eks_iam_node_group_arn
  endpoint_public_access = false
  security_group_ids     = [aws_security_group.eks.id, module.eks.cluster_security_group_id]
  desired_size           = each.value.desired_size
  max_size               = each.value.max_size
  min_size               = each.value.min_size
  image_id               = each.value.image_id
  instance_type          = each.value.instance_type
  disk_size              = "200"
  volume_type            = "gp3"
  AmazonEKSWorkerNodePolicy_attachment          = module.eks.AmazonEKSWorkerNodePolicy
  AmazonEKS_CNI_Policy_attachment               = module.eks.AmazonEKS_CNI_Policy
  AmazonEC2ContainerRegistryReadOnly_attachment = module.eks.AmazonEC2ContainerRegistryReadOnly

  tags_basic = merge(local.common_tags, {
    Name               = local.eks_cluster_name
    tag_component_name = "eks"
    tag_jira    = ""
    tag_cost_center = "platform-not-a-tf"

  })
}


output "api_server_url" {
  value = module.eks.endpoint
}
