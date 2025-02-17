#!/bin/bash

set -e  # 오류 발생 시 즉시 종료
set -o pipefail

# AWS 리전
AWS_REGION="ap-northeast-2"

# 생성된 리소스 ID 가져오기
EKS_CLUSTER_NAME="DevEKS"
VPC_ID=$(aws ec2 describe-vpcs --filters Name=cidr-block,Values=10.0.0.0/16 --query "Vpcs[0].VpcId" --output text)
PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets --filters Name=cidr-block,Values=10.0.1.0/24 --query "Subnets[0].SubnetId" --output text)
EKS_PRIVATE_SUBNET_A_ID=$(aws ec2 describe-subnets --filters Name=cidr-block,Values=10.0.2.0/24 --query "Subnets[0].SubnetId" --output text)
EKS_PRIVATE_SUBNET_B_ID=$(aws ec2 describe-subnets --filters Name=cidr-block,Values=10.0.3.0/24 --query "Subnets[0].SubnetId" --output text)
IGW_ID=$(aws ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC_ID --query "InternetGateways[0].InternetGatewayId" --output text)
NAT_GW_ID=$(aws ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID --query "NatGateways[0].NatGatewayId" --output text)
EIP_ALLOC_ID=$(aws ec2 describe-addresses --query "Addresses[?Domain=='vpc'].AllocationId" --output text)

# --------------------------
# EKS 노드 그룹 삭제
# --------------------------
echo "🛑 EKS 노드 그룹 삭제 중..."
aws eks delete-nodegroup --cluster-name $EKS_CLUSTER_NAME --nodegroup-name eks-node-group --region $AWS_REGION
sleep 60  # 노드 그룹 삭제 대기

# --------------------------
# EKS 클러스터 삭제
# --------------------------
echo "🛑 EKS 클러스터 삭제 중..."
aws eks delete-cluster --name $EKS_CLUSTER_NAME --region $AWS_REGION
sleep 60  # 클러스터 삭제 대기

# EKS 보안그룹 삭제 
if [ -n "$EKS_SECURITY_GROUP_ID" ]; then
    echo "🛑 EKS 보안 그룹 삭제 중..."
    aws ec2 delete-security-group --group-id $EKS_SECURITY_GROUP_ID --region $AWS_REGION
    echo "✅ EKS 보안 그룹 삭제 완료: $EKS_SECURITY_GROUP_ID"
else
    echo "⚠️ EKS 보안 그룹을 찾을 수 없음. 이미 삭제되었을 수 있음."
fi

# --------------------------
# ALB Controller Launch Template 삭제
# --------------------------
echo "🛑 ALB Controller Launch Template 삭제 중..."
if [ -n "$LAUNCH_TEMPLATE_ID" ]; then
    aws ec2 delete-launch-template --launch-template-id $LAUNCH_TEMPLATE_ID --region $AWS_REGION
fi

# --------------------------
# ALB Controller IAM 정책 삭제
# --------------------------
echo "🛑 ALB Controller IAM 정책 삭제 중..."
ALB_POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$ALB_POLICY_NAME'].Arn" --output text)

if [ -n "$ALB_POLICY_ARN" ]; then
    aws iam detach-role-policy --role-name $ALB_ROLE_NAME --policy-arn $ALB_POLICY_ARN
    aws iam delete-policy --policy-arn $ALB_POLICY_ARN
    echo "✅ ALB Controller IAM 정책 삭제 완료"
else
    echo "⚠️ ALB Controller IAM 정책을 찾을 수 없음. 이미 삭제되었을 수 있음."
fi

# --------------------------
# NAT 게이트웨이 삭제
# --------------------------
echo "🛑 NAT 게이트웨이 삭제 중..."
aws ec2 delete-nat-gateway --nat-gateway-id $NAT_GW_ID --region $AWS_REGION
sleep 30  # NAT 게이트웨이 삭제 대기

# EIP 해제
echo "🛑 EIP 해제 중..."
aws ec2 release-address --allocation-id $EIP_ALLOC_ID --region $AWS_REGION

# --------------------------
# 인터넷 게이트웨이 삭제
# --------------------------
echo "🛑 인터넷 게이트웨이 삭제 중..."
aws ec2 detach-internet-gateway --internet-gateway-id $IGW_ID --vpc-id $VPC_ID --region $AWS_REGION
aws ec2 delete-internet-gateway --internet-gateway-id $IGW_ID --region $AWS_REGION

# --------------------------
# IAM 역할 삭제
# --------------------------
echo "🛑 IAM 역할 삭제 중..."
aws iam detach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam detach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy
aws iam detach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam detach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSVPCResourceController
aws iam detach-role-policy --role-name EKSRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam delete-role --role-name EKSRole

aws iam detach-role-policy --role-name EKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
aws iam detach-role-policy --role-name EKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
aws iam detach-role-policy --role-name EKSNodeRole --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
aws iam delete-role --role-name EKSNodeRole

aws iam detach-role-policy --role-name ALBControllerRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
aws iam detach-role-policy --role-name ALBControllerRole --policy-arn arn:aws:iam::aws:policy/AmazonEKSServicePolicy
aws iam delete-role --role-name ALBControllerRole

aws iam delete-role --role-name $ALB_ROLE_NAME || echo "⚠️ ALB Controller IAM 역할이 존재하지 않음. 이미 삭제되었을 수 있음."

# --------------------------
# RDS 삭제
# --------------------------
echo "🛑 RDS 인스턴스 삭제 중..."
aws rds delete-db-instance --db-instance-identifier $RDS_INSTANCE_ID --skip-final-snapshot --region $AWS_REGION
sleep 120  # RDS 삭제 대기

# RDS 서브넷 그룹 삭제
echo "🛑 RDS 서브넷 그룹 삭제 중..."
aws rds delete-db-subnet-group --db-subnet-group-name $RDS_SUBNET_GROUP_NAME --region $AWS_REGION

# RDS 보안 그룹 삭제
echo "🛑 RDS 보안 그룹 삭제 중..."
RDS_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters Name=group-name,Values=RDSSecurityGroup --query "SecurityGroups[0].GroupId" --output text)
aws ec2 delete-security-group --group-id $RDS_SECURITY_GROUP_ID --region $AWS_REGION

echo "✅ RDS 관련 리소스 삭제 완료"

# --------------------------
# CloudWatch Logs 삭제
# --------------------------
echo "🛑 CloudWatch 로그 그룹 삭제 중..."
LOG_GROUP_NAME="/aws/eks/$EKS_CLUSTER_NAME/cluster"
aws logs delete-log-group --log-group-name $LOG_GROUP_NAME --region $AWS_REGION

echo "✅ CloudWatch 로그 그룹 삭제 완료"

# --------------------------
# CloudWatch Logs 정책 삭제
# --------------------------
echo "🛑 CloudWatch Logs IAM 정책 삭제 중..."
CLOUDWATCH_POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$CLOUDWATCH_POLICY_NAME'].Arn" --output text)

if [ -n "$CLOUDWATCH_POLICY_ARN" ]; then
    aws iam detach-role-policy --role-name EKSRole --policy-arn $CLOUDWATCH_POLICY_ARN
    aws iam delete-policy --policy-arn $CLOUDWATCH_POLICY_ARN
    echo "✅ CloudWatch Logs IAM 정책 삭제 완료"
else
    echo "⚠️ CloudWatch Logs IAM 정책을 찾을 수 없음. 이미 삭제되었을 수 있음."
fi

# --------------------------
# EKS 클러스터 로깅 비활성화
# --------------------------
echo "🛑 EKS 클러스터 로깅 비활성화 중..."
aws eks update-cluster-config --name $EKS_CLUSTER_NAME --logging '{"clusterLogging":[{"types":["api","audit","authenticator","controllerManager","scheduler"],"enabled":false}]}' --region $AWS_REGION
echo "✅ EKS 클러스터 로깅 비활성화 완료"

echo "🎉 모든 RDS 및 CloudWatch 관련 리소스 삭제 완료!"

# --------------------------
# 서브넷 삭제
# --------------------------
echo "🛑 서브넷 삭제 중..."
for SUBNET in $PUBLIC_SUBNET_ID $EKS_PRIVATE_SUBNET_A_ID $EKS_PRIVATE_SUBNET_B_ID; do
  aws ec2 delete-subnet --subnet-id $SUBNET --region $AWS_REGION
done

echo "🛑 RDS 프라이빗 서브넷 삭제 중..."

if [ -n "$RDS_PRIVATE_SUBNET_A_ID" ]; then
    aws ec2 delete-subnet --subnet-id $RDS_PRIVATE_SUBNET_A_ID --region $AWS_REGION
    echo "✅ RDS Private Subnet A 삭제 완료: $RDS_PRIVATE_SUBNET_A_ID"
else
    echo "⚠️ RDS Private Subnet A를 찾을 수 없음. 이미 삭제되었을 수 있음."
fi

if [ -n "$RDS_PRIVATE_SUBNET_B_ID" ]; then
    aws ec2 delete-subnet --subnet-id $RDS_PRIVATE_SUBNET_B_ID --region $AWS_REGION
    echo "✅ RDS Private Subnet B 삭제 완료: $RDS_PRIVATE_SUBNET_B_ID"
else
    echo "⚠️ RDS Private Subnet B를 찾을 수 없음. 이미 삭제되었을 수 있음."
fi

echo "🎉 RDS 프라이빗 서브넷 삭제 완료!"

# --------------------------
# 라우트 테이블 삭제
# --------------------------
echo "🛑 라우트 테이블 삭제 중..."
PUBLIC_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID --query "RouteTables[0].RouteTableId" --output text)
PRIVATE_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID --query "RouteTables[1].RouteTableId" --output text)

aws ec2 delete-route-table --route-table-id $PUBLIC_ROUTE_TABLE_ID --region $AWS_REGION
aws ec2 delete-route-table --route-table-id $PRIVATE_ROUTE_TABLE_ID --region $AWS_REGION

# --------------------------
# VPC 삭제
# --------------------------
echo "🛑 VPC 삭제 중..."
aws ec2 delete-vpc --vpc-id $VPC_ID --region $AWS_REGION

echo "✅ 모든 AWS 리소스 삭제 완료!"
