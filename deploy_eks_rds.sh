#!/bin/bash

set -e  # 오류 발생 시 즉시 종료
set -o pipefail

# AWS 리전 설정
AWS_REGION="ap-northeast-2"
VPC_CIDR="10.0.0.0/16"
PUBLIC_SUBNET_CIDR="10.0.1.0/24"
EKS_PRIVATE_SUBNET_A_CIDR="10.0.2.0/24"
EKS_PRIVATE_SUBNET_B_CIDR="10.0.3.0/24"
RDS_PRIVATE_SUBNET_A_CIDR="10.0.4.0/24"
RDS_PRIVATE_SUBNET_B_CIDR="10.0.5.0/24"

# --------------------------
# IAM 역할 생성 (EKS용)
# --------------------------

# EKS IAM 역할 생성
EKS_ROLE_ARN=$(aws iam create-role --role-name EKSRole --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "eks.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}' --query "Role.Arn" --output text)

# EKS IAM 역할에 정책 추가
aws iam attach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam attach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy
aws iam attach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSVPCResourceController
aws iam attach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly

echo "✅ EKS IAM 역할 생성 및 정책 연결 완료: $EKS_ROLE_ARN"


# --------------------------
# VPC 및 서브넷 생성
# --------------------------

# VPC 생성
VPC_ID=$(aws ec2 create-vpc --cidr-block $VPC_CIDR --region $AWS_REGION --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support "{\"Value\":true}"
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames "{\"Value\":true}"
echo "✅ VPC 생성 완료: $VPC_ID"

# 서브넷 생성
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $PUBLIC_SUBNET_CIDR --availability-zone ${AWS_REGION}a --query "Subnet.SubnetId" --output text)
EKS_PRIVATE_SUBNET_A_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $EKS_PRIVATE_SUBNET_A_CIDR --availability-zone ${AWS_REGION}a --query "Subnet.SubnetId" --output text)
EKS_PRIVATE_SUBNET_B_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $EKS_PRIVATE_SUBNET_B_CIDR --availability-zone ${AWS_REGION}c --query "Subnet.SubnetId" --output text)
RDS_PRIVATE_SUBNET_A_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $RDS_PRIVATE_SUBNET_A_CIDR --availability-zone ${AWS_REGION}a --query "Subnet.SubnetId" --output text)
RDS_PRIVATE_SUBNET_B_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block $RDS_PRIVATE_SUBNET_B_CIDR --availability-zone ${AWS_REGION}c --query "Subnet.SubnetId" --output text)
echo "✅ 서브넷 생성 완료"

# --------------------------
# 인터넷 및 NAT 게이트웨이 설정
# --------------------------

# 인터넷 게이트웨이 생성 및 연결
IGW_ID=$(aws ec2 create-internet-gateway --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
echo "✅ 인터넷 게이트웨이 생성 완료: $IGW_ID"

# NAT 게이트웨이 생성
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query "AllocationId" --output text)
NAT_GW_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUBNET_ID --allocation-id $EIP_ALLOC_ID --query "NatGateway.NatGatewayId" --output text)
echo "✅ NAT 게이트웨이 생성 완료: $NAT_GW_ID"

# 퍼블릭 라우트 테이블 생성
PUBLIC_ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query "RouteTable.RouteTableId" --output text)
echo "✅ 퍼블릭 라우트 테이블 생성 완료: $PUBLIC_ROUTE_TABLE_ID"

# 퍼블릭 라우트 추가 (인터넷 게이트웨이 연결)
aws ec2 create-route --route-table-id $PUBLIC_ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
echo "✅ 퍼블릭 라우트 추가 완료"

# 퍼블릭 서브넷과 퍼블릭 라우트 테이블 연결
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_ID --route-table-id $PUBLIC_ROUTE_TABLE_ID
echo "✅ 퍼블릭 서브넷 라우트 테이블 연결 완료"

# 프라이빗 라우트 테이블 생성
PRIVATE_ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query "RouteTable.RouteTableId" --output text)
echo "✅ 프라이빗 라우트 테이블 생성 완료: $PRIVATE_ROUTE_TABLE_ID"

# 프라이빗 라우트 추가 (NAT 게이트웨이 연결)
aws ec2 create-route --route-table-id $PRIVATE_ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID
echo "✅ 프라이빗 라우트 추가 완료"

# 프라이빗 서브넷과 프라이빗 라우트 테이블 연결
aws ec2 associate-route-table --subnet-id $EKS_PRIVATE_SUBNET_A_ID --route-table-id $PRIVATE_ROUTE_TABLE_ID
aws ec2 associate-route-table --subnet-id $EKS_PRIVATE_SUBNET_B_ID --route-table-id $PRIVATE_ROUTE_TABLE_ID
echo "✅ 프라이빗 서브넷 라우트 테이블 연결 완료"

# --------------------------
# EKS 클러스터 생성
# --------------------------

# EKS 클러스터 생성
EKS_ROLE_ARN=$(aws iam create-role --role-name EKSRole --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "eks.amazonaws.com"}, "Action": "sts:AssumeRole"}]
}' --query "Role.Arn" --output text)

aws iam attach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam attach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy

EKS_CLUSTER_NAME="DevEKS"
aws eks create-cluster --name $EKS_CLUSTER_NAME --role-arn $EKS_ROLE_ARN --resources-vpc-config subnetIds=$EKS_PRIVATE_SUBNET_A_ID,$EKS_PRIVATE_SUBNET_B_ID --region $AWS_REGION
echo "✅ EKS 클러스터 생성 완료"

# EKS 클러스터 보안 그룹 생성
EKS_SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name EKSSecurityGroup --description "EKS Cluster Security Group" --vpc-id $VPC_ID --query "GroupId" --output text)

# 보안 그룹 태그 추가
aws ec2 create-tags --resources $EKS_SECURITY_GROUP_ID --tags Key=Name,Value=EKSSecurityGroup

echo "✅ EKS 보안 그룹 생성 완료: $EKS_SECURITY_GROUP_ID"

# --------------------------
# ALB Controller launch template 생성성
# --------------------------

# ALB Controller IAM 역할 생성
ALB_ROLE_ARN=$(aws iam create-role --role-name ALBControllerRole --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "eks.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}' --query "Role.Arn" --output text)

aws iam attach-role-policy --role-name ALBControllerRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam attach-role-policy --role-name ALBControllerRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy

echo "✅ ALB Controller IAM 역할 생성 완료"

ALB_POLICY_ARN=$(aws iam create-policy --policy-name ALBControllerPolicy --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "elasticloadbalancing:*",
                "ec2:Describe*",
                "iam:CreateServiceLinkedRole",
                "iam:GetRole",
                "iam:ListRoles",
                "iam:PassRole",
                "cognito-idp:DescribeUserPoolClient",
                "acm:ListCertificates",
                "acm:DescribeCertificate"
            ],
            "Resource": "*"
        }
    ]
}' --query "Policy.Arn" --output text)

# ALB Controller 역할에 정책 연결
aws iam attach-role-policy --role-name ALBControllerRole --policy-arn $ALB_POLICY_ARN

echo "✅ ALB Controller IAM 정책 생성 및 연결 완료: $ALB_POLICY_ARN"

# ALB Controller Launch Template 생성
LAUNCH_TEMPLATE_ID=$(aws ec2 create-launch-template --launch-template-name ALBControllerTemplate --launch-template-data '{
    "UserData": "'$(echo -n '#!/bin/bash
set -o xtrace

# Mark that ALB has been installed
touch /tmp/alb_installed

# Install AWS CLI & jq
yum install -y aws-cli jq

# Install Kubernetes tools
if ! command -v kubectl &> /dev/null; then
  curl -o kubectl https://amazon-eks.s3.amazonaws.com/latest/kubernetes_version/bin/linux/amd64/kubectl
  chmod +x ./kubectl
  mv ./kubectl /usr/local/bin/
fi

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Deploy AWS Load Balancer Controller
kubectl apply -k github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller --set clusterName=DevEKS --set serviceAccount.create=false --set serviceAccount.name=aws-load-balancer-controller
' | base64 -w 0)'  
}' --query "LaunchTemplate.LaunchTemplateId" --output text)

echo "✅ ALB Controller Launch Template 생성 완료: $LAUNCH_TEMPLATE_ID"

# EKS 노드 그룹 생성
EKS_NODE_ROLE_ARN=$(aws iam create-role --role-name EKSNodeRole --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "ec2.amazonaws.com"}, "Action": "sts:AssumeRole"}]
}' --query "Role.Arn" --output text)

aws iam attach-role-policy --role-name EKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam attach-role-policy --role-name EKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam attach-role-policy --role-name EKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy

aws eks create-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name eks-node-group \
  --subnets $EKS_PRIVATE_SUBNET_A_ID $EKS_PRIVATE_SUBNET_B_ID --node-role $EKS_NODE_ROLE_ARN \
  --scaling-config minSize=2,maxSize=3,desiredSize=2 --instance-types t3.medium \
  --launch-template "id=$LAUNCH_TEMPLATE_ID,version=1"

echo "✅ ALB Controller를 포함한 EKS Node Group 생성 완료"

# --------------------------
# RDS 관련 설정정
# --------------------------

# RDS 서브넷 그룹 생성
aws rds create-db-subnet-group --db-subnet-group-name dev-rds-subnet-group --db-subnet-group-description "RDS subnet group" --subnet-ids $RDS_PRIVATE_SUBNET_A_ID $RDS_PRIVATE_SUBNET_B_ID
echo "✅ RDS 서브넷 그룹 생성 완료"

# RDS 서브넷 그룹 생성
aws rds create-db-subnet-group --db-subnet-group-name dev-rds-subnet-group \
  --db-subnet-group-description "RDS subnet group for Multi-AZ" \
  --subnet-ids $RDS_PRIVATE_SUBNET_A_ID $RDS_PRIVATE_SUBNET_B_ID \
  --region $AWS_REGION

echo "✅ RDS 서브넷 그룹 생성 완료"

# RDS 인스턴스 생성 (Multi-AZ)
aws rds create-db-instance --db-instance-identifier dev-rds \
  --engine mysql --engine-version "8.0" \
  --db-instance-class db.t3.micro --allocated-storage 20 \
  --multi-az --master-username admin --master-user-password "SecurePassword123!" \
  --db-subnet-group-name dev-rds-subnet-group --vpc-security-groups $RDS_SECURITY_GROUP_ID \
  --region $AWS_REGION
# RDS 보안 그룹 생성
RDS_SECURITY_GROUP_ID=$(aws ec2 create-security-group --group-name RDSSecurityGroup \
  --description "Allow MySQL access from EKS nodes" --vpc-id $VPC_ID --query "GroupId" --output text)

# RDS 보안 그룹에 인바운드 규칙 추가 (EKS에서 MySQL 접속 허용)
aws ec2 authorize-security-group-ingress --group-id $RDS_SECURITY_GROUP_ID \
  --protocol tcp --port 3306 --source-group $EKS_SECURITY_GROUP_ID --region $AWS_REGION

# 보안 그룹 태그 추가
aws ec2 create-tags --resources $RDS_SECURITY

echo "✅ RDS Multi-AZ 인스턴스 생성 완료"

# --------------------------
# CloudWatch 관련 설정정
# --------------------------

# CloudWatch 로그 그룹 생성
LOG_GROUP_NAME="/aws/eks/$EKS_CLUSTER_NAME/cluster"
aws logs create-log-group --log-group-name $LOG_GROUP_NAME --region $AWS_REGION || echo "로그 그룹 이미 존재함"
echo "✅ CloudWatch 로그 그룹 생성 완료: $LOG_GROUP_NAME"


# CloudWatch Logs 정책 생성
CLOUDWATCH_POLICY_ARN=$(aws iam create-policy --policy-name EKSCloudWatchLogsPolicy --policy-document '{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:DescribeLogStreams",
            "logs:PutLogEvents"
        ],
        "Resource": [
            "arn:aws:logs:'"$AWS_REGION"':'$(aws sts get-caller-identity --query Account --output text)':log-group:/aws/eks/DevEKS/cluster:*"
        ]
    }]
}' --query "Policy.Arn" --output text)

# EKS IAM 역할에 CloudWatch Logs 정책 연결
aws iam attach-role-policy --role-name EKSRole --policy-arn $CLOUDWATCH_POLICY_ARN

echo "✅ CloudWatch Logs IAM 정책 생성 및 연결 완료: $CLOUDWATCH_POLICY_ARN"

# EKS 클러스터 로깅 설정
aws eks update-cluster-config --name $EKS_CLUSTER_NAME --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":true}]}' --region $AWS_REGION
echo "✅ EKS 클러스터 로깅 활성화 완료"

echo "🎉 AWS 리소스 생성 완료!"
echo "✅ VPC ID: $VPC_ID"
echo "✅ EKS Cluster: $EKS_CLUSTER_NAME"
echo "✅ RDS Instance: dev-rds"
