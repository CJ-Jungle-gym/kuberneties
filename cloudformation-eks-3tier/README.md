# 프로젝트 구조
cloudformation-eks-3tier/
│── master.yml                # 모든 스택을 포함하는 마스터 파일
│── vpc.yml                   # VPC 및 네트워크 설정
│── eks-cluster.yml           # EKS 클러스터 및 노드 그룹 설정
│── alb.yml                   # ALB 및 Ingress Controller 설정
│── rds.yml                   # RDS (MySQL) 데이터베이스 설정
│── iam.yml                   # IAM 역할 및 정책 설정
│── security.yml               # 보안 그룹 및 네트워크 정책
│── cloudwatch.yml            # CloudWatch 모니터링 설정

