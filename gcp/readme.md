# Roteiro

O que iremos fazer?

1. Configuração do Cluster Kubernetes
2. Configuração do Traefik
3. Configuração do Longhorn
4. Criação do certificado não válido
5. Configuração do ELB
6. Configuração do DNS


ativar as apis do google
configurar o dns


# 1 - Configuração do Cluster Kubernetes
```sh
# Creating a managed instance group
$ gcloud compute instance-templates create multicloud \
   --region=us-east1 \
   --network=default \
   --boot-disk-size=60GB \
   --subnet=default \
   --tags=allow-health-check \
   --image-family=debian-12 \
   --image-project=debian-cloud \
   --machine-type=e2-medium \
    --metadata=rancher-server=<IP_OU_DNS_DO_RANCHER>,rancher-token=<TOKEN_DO_RANCHER>,rancher-ca-checksum=<CA_CHECKSUM_DO_RANCHER> \
    --metadata-from-file startup-script=install-k8s.sh

# Create the managed instance group based on the template.
$ gcloud compute instance-groups managed create multicloud-backend \
   --template=multicloud --size=3 --zone=us-east1-b

# Mantenha 3 nós para o cluster RKE2 com etcd/controlplane.
# Reduzir o MIG para 1 nó quebra o quorum do etcd e o Rancher passa a mostrar
# erro de comunicação com o API server, por exemplo timeout em https://10.43.0.1:443/readyz.
$ gcloud compute instance-groups managed resize multicloud-backend \
    --size=3 \
    --zone=us-east1-b

# Adding a named port to the instance group
$ gcloud compute instance-groups set-named-ports multicloud-backend \
    --named-ports http:30700 \
    --zone us-east1-b




# Configuring a firewall rule
$ gcloud compute firewall-rules create fw-allow-health-check \
    --network=default \
    --action=allow \
    --direction=ingress \
    --source-ranges=130.211.0.0/22,35.191.0.0/16 \
    --target-tags=allow-health-check \
    --rules=tcp:30700

```

# banco dados 
$ kubectl -n jonjon run cockroachdb -it \
--image=cockroachdb/cockroach:v23.2.31 \
--rm \
--restart=Never \
-- sql \
--insecure \
--host=cockroachdb.jonjon.svc.cluster.local


# 2 - Configuração do Traefik

O RKE2 já vem com o Traefik embutido como ingress controller. Não instale o Traefik v1.7 legado (`containous/traefik`), porque ele conflita com o chart `rke2-traefik` atual.

Verifique o serviço do Traefik e confirme a NodePort da porta `web`:
```sh
$ kubectl --namespace=kube-system get svc rke2-traefik
```

O dashboard vem desabilitado por padrão. Para habilitá-lo e expor a porta HTTP como NodePort 30700, aplique o `HelmChartConfig`:
```sh
$ kubectl apply -f rke2-traefik-config.yaml
$ kubectl --namespace=kube-system get pods -l app.kubernetes.io/name=rke2-traefik -w
```

O Service deve ficar como `NodePort`, com a porta `web` exposta em `30700`:
```sh
$ kubectl --namespace=kube-system get svc rke2-traefik

NAME           TYPE       CLUSTER-IP     EXTERNAL-IP   PORT(S)
rke2-traefik   NodePort   10.43.x.x      <none>        80:30700/TCP,443:<porta>/TCP
```

Agora configure o DNS pelo qual o Traefik irá responder em `traefik.yaml` e aplique a rota do dashboard:
```sh
$ kubectl apply -f traefik.yaml
```

Teste direto pela NodePort antes de mexer no Load Balancer:
```sh
$ curl -H "Host: traefik.multicloud-devops-ninja.pt" http://<IP_DO_NO>:30700/dashboard/
```

## Troubleshooting do cluster GCP

Se o Rancher mostrar erro parecido com `Failed to communicate with API server` ou timeout em `https://10.43.0.1:443/readyz`, valide primeiro estes pontos:

```sh
$ gcloud compute instance-groups managed describe multicloud-backend \
    --zone=us-east1-b \
    --format="get(targetSize)"

$ gcloud compute instance-groups managed list-instances multicloud-backend \
    --zone=us-east1-b

$ kubectl --context rancher -n fleet-default get machines.cluster.x-k8s.io -o wide
```

O cluster RKE2 com nós `--etcd --controlplane --worker` precisa manter 3 nós saudáveis. Se o MIG foi reduzido para 1, o etcd perde quorum e o Rancher pode ficar preso esperando probes de `etcd`, `kube-apiserver` e `kubelet` em machines antigas. Nesse estado, recriar o cluster GCP no Rancher costuma ser mais limpo do que tentar reaproveitar o estado antigo.

# 3 - Configuração Longhorn

*.multicloud-devops-ninja.pt

# 4 -  Criação do certificado não válido

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
  
  *.multicloud.ml  

  multicloud

```sh

# ENVIAR O ARQUIVO CERT QUE CRIARMOS PARA multicloud.ml

# O codigo abaixo fazer o provisionamento automatico


# multi-cloud-2

# $ gcloud compute ssl-certificates create multicloud \
#         --certificate=certificate-file \
#         --private-key=private-key-file \
#         --global
    
#  nome do certificado que subi - devops-ninja
```


# 5 - Configuração do ELB


```sh 


# Reserving an external IP address
$ gcloud compute addresses create lb-ipv4-1 \
    --ip-version=IPV4 \
    --global

# Describe
$ gcloud compute addresses describe lb-ipv4-1 \
    --format="get(address)" \
    --global

#  8.232.35.145

# SETUP

# Healthcheck no backend HTTP do Traefik. O HTTPS termina no Load Balancer.
$ gcloud compute health-checks create http http-basic-check \
    --port 30700 \
    --request-path /api/overview \
    --host traefik.multicloud-devops-ninja.pt

# Backend Service
$ gcloud compute backend-services create web-backend-service \
    --protocol=HTTP \
    --port-name=http \
    --health-checks=http-basic-check \
    --global



# Add your instance group as the backend to the backend service.
$ gcloud compute backend-services add-backend web-backend-service \
    --instance-group=multicloud-backend \
    --instance-group-zone=us-east1-b \
    --global


# Create a URL map to route the incoming requests to the default backend service.
$  gcloud compute url-maps create web-map-https \
    --default-service web-backend-service


# Criar um http proxy para fazer o  roteamento
$ gcloud compute target-https-proxies create https-lb-proxy \
    --url-map web-map-https --ssl-certificates devops-ninja
    
# Criar regra global de forwarding 
$ gcloud compute forwarding-rules create https-content-rule \
    --address=lb-ipv4-1\
    --global \
    --target-https-proxy=https-lb-proxy \
    --ports=443

```

# 6 - Configuração do DNS



