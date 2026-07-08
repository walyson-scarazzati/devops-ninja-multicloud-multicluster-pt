# Roteiro

O que iremos fazer?

## Parte 1
1. Criação de usuário do IAM e permissões
2. Criação da instância do RancherServer pela aws-cli
3. Configuração do Rancher.
4. Configuração do Cluster Kubernetes.
5. Deployment do cluster pela aws-cli.



## Parte 2
6. Configuração do Traefik
7. Configuração do Longhorn
8. Criação do certificado não válido
9. Configuração do ELB
10. Configuração do Route 53


Parabéns, com isso temos a primera parte da nossa infraestrutura. 
Estamos prontos para rodar nossa aplicação.


# Parte 1

## 1 - Criação de usuário do IAM e permissões e configuração da AWS-CLI

https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html


## 2 - Criação da instância do RancherServer pela aws-cli.

```sh 

# RANCHER SERVER

# --image-id              ami-0b6d9d3d33ba97d99
# --instance-type         t3.medium 
# --key-name              multicloud 
# --security-group-ids    sg-05f2fa573cc84684b 
# --subnet-id             subnet-0b14411a7e1837065

$ aws ec2 run-instances --image-id ami-0b6d9d3d33ba97d99 --count 1 --instance-type t3.medium --key-name multicloud --security-group-ids sg-05f2fa573cc84684b --subnet-id subnet-0b14411a7e1837065 --user-data file://rancher.sh --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=rancherserver}]' 'ResourceType=volume,Tags=[{Key=Name,Value=rancherserver}]' 

```


## 3 - Configuração do Rancher
Acessar o Rancher e configurar

https://44.200.171.155/

## 4 - Configuração do Cluster Kubernetes.
Criar o cluster pelo Rancher e configurar.



## 5 - Deployment do cluster pela aws-cli

`k8s.sh` lê `RANCHER_SERVER`, `RANCHER_TOKEN` e `RANCHER_CA_CHECKSUM` do ambiente (valores obtidos na tela de "Registrar Cluster" do Rancher). Antes de rodar o `run-instances`, exporte-os localmente e prefixe o `k8s.sh` com os `export` correspondentes ao gerar o user-data, ou injete-os via SSM Parameter Store / Secrets Manager — não deixe o token em texto plano no arquivo.

```sh
# --image-id ami-0b6d9d3d33ba97d99
# --count 3 
# --instance-type t3.large 
# --key-name multicloud 
# --security-group-ids sg-05f2fa573cc84684b  
# --subnet-id subnet-0ae0a71ee419dd27a
# --user-data file://k8s.sh

$ aws ec2 run-instances --image-id ami-0b6d9d3d33ba97d99 --count 3 --instance-type t3.large --key-name multicloud --security-group-ids sg-05f2fa573cc84684b --subnet-id subnet-0ae0a71ee419dd27a --user-data file://k8s.sh --block-device-mapping "[ { \"DeviceName\": \"/dev/sda1\", \"Ebs\": { \"VolumeSize\": 70 } } ]" --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=k8s}]' 'ResourceType=volume,Tags=[{Key=Name,Value=k8s}]'  
```

## Instalar o kubectl 

https://kubernetes.io/docs/tasks/tools/


# Parte 2

## 6 - Configuração do Traefik

O RKE2 já vem com o Traefik embutido como ingress controller, exposto via NodePort (ex.: `80:30700`, `443:32655`). Não é necessário instalar o Traefik v1.7 legado.

Verifique o serviço e a porta NodePort atribuída:
```sh
$ kubectl --namespace=kube-system get svc rke2-traefik
```

O dashboard vem desabilitado por padrão. Para habilitá-lo, copie `rke2-traefik-config.yaml` para o diretório de manifests do RKE2 em cada nó server (isso reconfigura o Helm chart embutido):
```sh
$ sudo cp rke2-traefik-config.yaml /var/lib/rancher/rke2/server/manifests/
$ kubectl --namespace=kube-system get pods -l app.kubernetes.io/name=rke2-traefik -w
```

**Atenção:** sobrescrever o `HelmChartConfig` do `rke2-traefik` reseta a seção `service`/`ports` do chart para os defaults dele, derrubando o `NodePort` original (`80:30700`, `443:32655`) que o ELB depende. Depois de aplicar o `HelmChartConfig`, restaure o Service manualmente:
```sh
$ kubectl patch svc rke2-traefik -n kube-system --type='json' -p '[
  {"op":"replace","path":"/spec/type","value":"NodePort"},
  {"op":"replace","path":"/spec/ports","value":[
    {"name":"web","port":80,"protocol":"TCP","targetPort":"web","nodePort":30700},
    {"name":"websecure","port":443,"protocol":"TCP","targetPort":"websecure","nodePort":32655},
    {"name":"traefik","port":9000,"protocol":"TCP","targetPort":"traefik","nodePort":30900}
  ]}
]'
```
Esse patch é manual e não sobrevive a um `helm-install-rke2-traefik` futuro (reinício de node, upgrade do chart etc.) — se o Service voltar a `ClusterIP`, repita o patch. TODO: substituir por um `valuesContent` no `HelmChartConfig` que preserve `service.type: NodePort` e os `nodePort` corretamente (a chave usada nas tentativas iniciais, `ports.<entrypoint>.expose`, não teve o efeito esperado nesse chart).

Depois de o pod reiniciar com o dashboard habilitado, ajuste o host em `traefik.yaml` e aplique a `IngressRoute` (usa a CRD do Traefik, não o `Ingress` padrão do Kubernetes, pois o dashboard só é servido via `api@internal`):
```sh
$ kubectl apply -f traefik.yaml
```
Teste com:
```sh
$ curl -H "Host: traefik.devops-ninja.me" http://localhost:30700/dashboard/
```


## 7 - Configuração do Longhorn
Pelo console do Rancher


## 8 - Criação do certificado
Criar certificado para nossos dominios:

 *.devops-ninja.me


```sh
> openssl req -new -x509 -keyout cert.pem -out cert.pem -days 365 -nodes
Country Name (2 letter code) [AU]:DE
State or Province Name (full name) [Some-State]:Germany
Locality Name (eg, city) []:nameOfYourCity
Organization Name (eg, company) [Internet Widgits Pty Ltd]:nameOfYourCompany
Organizational Unit Name (eg, section) []:nameOfYourDivision
Common Name (eg, YOUR name) []:*.example.com
Email Address []:webmaster@example.com
```


arn:aws:acm:us-east-1:257527264470:certificate/c4c32968-256c-44a7-98dd-8820fe34f55e

## 9 - Configuração do ELB

**Atenção:** o Security Group do load balancer, por padrão, costuma vir apenas com uma regra self-referencing (permite tráfego só de instâncias no próprio SG), o que bloqueia qualquer acesso público. Libere as portas do listener para a internet:
```sh
$ aws ec2 authorize-security-group-ingress --group-id <SG_DO_LOAD_BALANCER> --protocol tcp --port 443 --cidr 0.0.0.0/0
$ aws ec2 authorize-security-group-ingress --group-id <SG_DO_LOAD_BALANCER> --protocol tcp --port 80 --cidr 0.0.0.0/0
```

```sh
# LOAD BALANCER

# !! ESPECIFICAR O SECURITY GROUPS DO LOAD BALANCER

# --subnets subnet-0b14411a7e1837065 subnet-0d04b7671ba785eb9

$ aws elbv2 create-load-balancer --name multicloud --type application --subnets subnet-0b14411a7e1837065 subnet-0d04b7671ba785eb9
#	 "LoadBalancerArn": "arn:aws:elasticloadbalancing:us-east-1:257527264470:loadbalancer/app/multicloud/806cb06cba4ddcef"

# --vpc-id vpc-0f8086f9791778fba

# Health check e tráfego apontam para a NodePort do Traefik embutido do RKE2 (ex.: 30700 para a porta 80 do serviço).
# Consulte a porta atual com: kubectl --namespace=kube-system get svc rke2-traefik
# O matcher aceita 200 e 404: sem nenhuma app/Ingress deployada o Traefik responde 404, o que ainda é considerado "healthy" até a app subir.

$ aws elbv2 create-target-group --name multicloud --protocol HTTP --port 80 --vpc-id vpc-0f8086f9791778fba --health-check-port 30700 --health-check-path / --matcher HttpCode=200,404
#	 "TargetGroupArn": "arn:aws:elasticloadbalancing:us-east-1:257527264470:targetgroup/multicloud/a7646816b8be54a3",
	
	
# REGISTRAR OS TARGETS com override de porta para a NodePort do Traefik
$ aws elbv2 register-targets --target-group-arn arn:aws:elasticloadbalancing:us-east-1:257527264470:targetgroup/multicloud/a7646816b8be54a3 --targets Id=i-08912f784fdfac183,Port=30700 Id=i-074e053170604b8c9,Port=30700 Id=i-0a58302588cd6aebd,Port=30700

# Libere a faixa de NodePort do Kubernetes (30000-32767) no SG das instâncias, com origem = SG do load balancer:
$ aws ec2 authorize-security-group-ingress --group-id sg-05f2fa573cc84684b --protocol tcp --port 30000-32767 --source-group <SG_DO_LOAD_BALANCER>


i-08912f784fdfac183
i-074e053170604b8c9
i-0a58302588cd6aebd


# ARN DO Certificado - arn:aws:acm:us-east-1:984102645395:certificate/fa016001-254f-4127-b51a-61588b15c555
# HTTPS - CRIADO PRIMEIRO
$ aws elbv2 create-listener \
    --load-balancer-arn arn:aws:elasticloadbalancing:us-east-1:257527264470:loadbalancer/app/multicloud/806cb06cba4ddcef \
    --protocol HTTPS \
    --port 443 \
    --certificates CertificateArn=arn:aws:acm:us-east-1:257527264470:certificate/c4c32968-256c-44a7-98dd-8820fe34f55e   \
    --ssl-policy ELBSecurityPolicy-2016-08 --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:us-east-1:257527264470:targetgroup/multicloud/a7646816b8be54a3
#  "ListenerArn": "arn:aws:elasticloadbalancing:us-east-1:257527264470:listener/app/multicloud/806cb06cba4ddcef/08d23adac97ac74c"


$ aws elbv2 describe-target-health --target-group-arn targetgroup-arn

# DESCRIBE NO LISTENER
$ aws elbv2 describe-listeners --listener-arns arn:aws:elasticloadbalancing:us-east-1:984102645395:listener/app/multicloud/0c7e036793bff35e/a7386cf3e0dc3c0e


# banco dados 
$ kubectl -n jonjon run cockroachdb -it \
--image=cockroachdb/cockroach:v23.2.31 \
--rm \
--restart=Never \
-- sql \
--insecure \
--host=cockroachdb.jonjon.svc.cluster.local


```


## 10 - Configuração do Route 53
Pelo console da AWS



