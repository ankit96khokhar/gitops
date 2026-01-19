# Kubernetes Platform Engineering Guide

This repository contains comprehensive guidance and implementations for building a production-ready Kubernetes platform with GitOps, admission controllers, and security policies.

## Table of Contents

- [Overview](#overview)
- [EKS Cluster Management](#eks-cluster-management)
- [ArgoCD GitOps Setup](#argocd-gitops-setup)
- [App-of-Apps Pattern](#app-of-apps-pattern)
- [ApplicationSets for Scale](#applicationsets-for-scale)
- [Admission Controllers](#admission-controllers)
- [OPA Gatekeeper Setup](#opa-gatekeeper-setup)
- [Platform Security Policies](#platform-security-policies)
- [Testing and Validation](#testing-and-validation)
- [Production Best Practices](#production-best-practices)

## Overview

This guide covers the implementation of a complete Kubernetes platform engineering solution including:

- **GitOps**: ArgoCD with App-of-Apps pattern for declarative deployments
- **Progressive Delivery**: Argo Rollouts for canary deployments
- **Policy Enforcement**: OPA Gatekeeper for admission control
- **Service Mesh**: Istio integration for traffic management
- **Security**: Comprehensive platform policies for governance

## EKS Cluster Management

### Key Concepts

1. **Cluster Lifecycle Management**
   - Infrastructure as Code (Terraform/CloudFormation)
   - Node group management and scaling
   - Security groups and IAM roles
   - VPC and networking configuration

2. **Add-ons Management**
   - Core add-ons: EBS CSI, VPC CNI, CoreDNS
   - Observability: CloudWatch, Prometheus, Grafana
   - Security: Pod Security Standards, Network Policies

3. **Multi-Environment Strategy**
   - Environment isolation (dev/staging/prod)
   - Resource quotas and limits
   - RBAC and service accounts
   - Cost optimization

## ArgoCD GitOps Setup

### Installation on Minikube

```bash
# Start minikube with specific configuration
minikube start --cpus=2 --memory=2048m --nodes=2

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Port forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### ArgoCD Configuration

Key configurations for production:
- RBAC policies for team access
- SSO integration (OIDC/SAML)
- Repository credentials management
- Application sync policies
- Notification integrations

## App-of-Apps Pattern

### Repository Structure

```
gitops/
├── root-app.yaml                 # Root Application
├── apps/                         # Application definitions
│   └── nginx/
│       └── prod/
│           └── application.yaml
└── manifests/                    # Kubernetes manifests
    └── nginx/
        ├── deployment.yaml
        ├── service.yaml
        └── rollout.yaml
```

### Root Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ankit96khokhar/gitops.git
    targetRevision: HEAD
    path: apps
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Child Application Example

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-prod
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/ankit96khokhar/gitops.git
    targetRevision: HEAD
    path: manifests/nginx
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## ApplicationSets for Scale

ApplicationSets provide a declarative way to manage multiple Applications across:
- Multiple clusters (dev/staging/prod)
- Multiple teams and namespaces
- Multiple environments per application

### Multi-Cluster Example

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: nginx-multicluster
  namespace: argocd
spec:
  generators:
  - clusters: {}
  template:
    metadata:
      name: '{{name}}-nginx'
    spec:
      project: default
      source:
        repoURL: https://github.com/ankit96khokhar/gitops.git
        targetRevision: HEAD
        path: manifests/nginx
      destination:
        server: '{{server}}'
        namespace: nginx
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

## Admission Controllers

### Types and Use Cases

1. **Validating Admission Controllers**
   - Resource validation (CPU/memory limits)
   - Security policy enforcement
   - Naming conventions
   - Required labels and annotations

2. **Mutating Admission Controllers**
   - Automatic sidecar injection
   - Resource limit defaulting
   - Security context enforcement
   - Environment variable injection

### Custom vs Built-in Controllers

- **Built-in**: ResourceQuota, LimitRange, PodSecurityPolicy
- **Custom**: OPA Gatekeeper, Falco, Kyverno
- **Service Mesh**: Istio admission webhooks

## OPA Gatekeeper Setup

### Installation via Helm

```bash
# Add Gatekeeper Helm repository
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

# Install Gatekeeper
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --set validatingWebhookFailurePolicy=Ignore

# Verify installation
kubectl get pods -n gatekeeper-system
kubectl get crd | grep gatekeeper
```

### Key Components

1. **ConstraintTemplates**: Define policy logic using Rego
2. **Constraints**: Apply templates to specific resources
3. **Violations**: Track policy enforcement results
4. **Audit**: Continuous compliance monitoring

## Platform Security Policies

### Policy Categories

#### 1. Security Policies

**Deny Privileged Containers**
```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: denyprivileged
spec:
  crd:
    spec:
      names:
        kind: DenyPrivileged
      validation:
        openAPIV3Schema:
          type: object
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package denyprivileged
        
        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          container.securityContext.privileged == true
          msg := "Privileged containers are not allowed"
        }
        
        violation[{"msg": msg}] {
          container := input.review.object.spec.initContainers[_]
          container.securityContext.privileged == true
          msg := "Privileged init containers are not allowed"
        }
```

**Require Resource Limits**
```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: requireresources
spec:
  crd:
    spec:
      names:
        kind: RequireResources
      validation:
        openAPIV3Schema:
          type: object
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package requireresources
        
        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not container.resources.limits.cpu
          msg := sprintf("Container '%s' must specify CPU limits", [container.name])
        }
        
        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not container.resources.limits.memory
          msg := sprintf("Container '%s' must specify memory limits", [container.name])
        }
```

#### 2. Governance Policies

**Require Labels**
```yaml
apiVersion: templates.gatekeeper.sh/v1beta1
kind: ConstraintTemplate
metadata:
  name: requirelabels
spec:
  crd:
    spec:
      names:
        kind: RequireLabels
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package requirelabels
        
        violation[{"msg": msg}] {
          required := input.parameters.labels
          provided := input.review.object.metadata.labels
          missing := required[_]
          not provided[missing]
          msg := sprintf("Label '%s' is required", [missing])
        }
```

### Policy Organization Structure

```
platform-policies/
├── security/
│   ├── deny-privileged/
│   │   ├── template.yaml
│   │   └── constraint.yaml
│   ├── require-resources/
│   │   ├── template.yaml
│   │   └── constraint.yaml
│   └── security-context/
├── governance/
│   ├── require-labels/
│   │   ├── template.yaml
│   │   └── constraint.yaml
│   └── naming-conventions/
└── resource-management/
    ├── limit-ranges/
    └── resource-quotas/
```

## Testing and Validation

### Policy Testing Commands

**Test Resource Limits Policy**
```bash
# Deploy the ConstraintTemplate
kubectl apply -f require-resources-template.yaml

# Wait for template to be ready
kubectl wait --for=condition=Ready constrainttemplate/requireresources --timeout=60s

# Deploy the Constraint
kubectl apply -f require-resources-constraint.yaml

# Test with non-compliant pod (should be blocked)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-no-resources
spec:
  containers:
  - name: nginx
    image: nginx:latest
EOF

# Test with compliant pod (should succeed)
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-with-resources
spec:
  containers:
  - name: nginx
    image: nginx:latest
    resources:
      limits:
        cpu: "500m"
        memory: "512Mi"
      requests:
        cpu: "250m"
        memory: "256Mi"
EOF
```

**Check Policy Violations**
```bash
# View constraint status
kubectl get requireresources

# Check violations
kubectl describe requireresources require-pod-resources

# View Gatekeeper audit results
kubectl get violations -A
```

### Validation Checklist

- [ ] ConstraintTemplates deploy successfully
- [ ] Constraints are created and ready
- [ ] Non-compliant resources are blocked
- [ ] Compliant resources are allowed
- [ ] Violations are properly recorded
- [ ] Audit reports show compliance status

## Production Best Practices

### 1. Policy Development Lifecycle

1. **Development**: Write and test policies in dev environment
2. **Testing**: Validate against real workloads in staging
3. **Gradual Rollout**: Deploy in warn mode before enforcement
4. **Monitoring**: Track violations and performance impact
5. **Maintenance**: Regular policy updates and reviews

### 2. Deployment Strategy

- Use `failurePolicy: Ignore` during initial rollout
- Implement policies in `warn` mode first
- Gradually enable enforcement mode
- Monitor admission webhook performance
- Set up proper alerting for policy violations

### 3. Performance Considerations

- Optimize Rego policy logic
- Set resource limits for Gatekeeper pods
- Monitor admission webhook latency
- Use exemptions for system namespaces
- Consider policy complexity impact

### 4. Monitoring and Observability

```bash
# Gatekeeper metrics
kubectl get --raw /metrics | grep gatekeeper

# Violation tracking
kubectl get violations -A -o wide

# Audit results
kubectl logs -n gatekeeper-system -l control-plane=audit-controller
```

### 5. Backup and Disaster Recovery

- Version control all policy definitions
- Document policy exemptions and rationale
- Test policy restoration procedures
- Maintain policy inventory and compliance reports

## Troubleshooting

### Common Issues

1. **ConstraintTemplate not ready**
   - Check Rego syntax errors
   - Verify target specification
   - Review Gatekeeper controller logs

2. **Policies not enforcing**
   - Ensure Constraints reference correct templates
   - Check namespace selectors
   - Verify webhook configuration

3. **Performance issues**
   - Review policy complexity
   - Check resource allocation
   - Monitor webhook timeouts

### Useful Commands

```bash
# Check Gatekeeper status
kubectl get constrainttemplates
kubectl get constraints
kubectl describe gatekeeper-violations

# View logs
kubectl logs -n gatekeeper-system -l control-plane=controller-manager
kubectl logs -n gatekeeper-system -l control-plane=audit-controller

# Debug webhook
kubectl get validatingadmissionpolicies
kubectl describe validatingwebhookconfigurations gatekeeper-validating-webhook-configuration
```

## Contributing

1. Follow the established policy structure
2. Test all policies in development environment
3. Document policy purpose and examples
4. Include violation scenarios in tests
5. Update this README with new policies

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [OPA Gatekeeper Documentation](https://open-policy-agent.github.io/gatekeeper/)
- [Kubernetes Admission Controllers](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/)
- [Argo Rollouts Documentation](https://argoproj.github.io/argo-rollouts/)
- [Istio Service Mesh](https://istio.io/)

---

This guide provides a comprehensive foundation for implementing Kubernetes platform engineering practices with GitOps and policy enforcement. Adapt the configurations and policies to match your organization's specific requirements and security standards.

