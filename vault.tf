apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: require-pod-securitycontext
spec:
  validationActions: [Audit]
  evaluation:
    background:
      enabled: true
  matchConstraints:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values: [blue, shared]
    resourceRules:
    - apiGroups: [""]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [pods]
  variables:
  - name: sc
    expression: "object.spec.?securityContext.orValue({})"
  validations:
  - expression: "has(variables.sc.runAsUser)"
    message: "spec.securityContext.runAsUser requis."
  - expression: "has(variables.sc.runAsGroup)"
    message: "spec.securityContext.runAsGroup requis."
  - expression: "has(variables.sc.fsGroup)"
    message: "spec.securityContext.fsGroup requis."


apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: require-no-privilege-escalation
spec:
  validationActions: [Audit]
  evaluation:
    background:
      enabled: true
  matchConstraints:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values: [blue, shared]
    resourceRules:
    - apiGroups: [""]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [pods]
  variables:
  - name: allContainers
    expression: >-
      object.spec.containers
      + object.spec.?initContainers.orValue([])
      + object.spec.?ephemeralContainers.orValue([])
  validations:
  - expression: >-
      variables.allContainers.all(c,
        c.?securityContext.?allowPrivilegeEscalation.orValue(true) == false)
    messageExpression: >-
      "allowPrivilegeEscalation doit être présent et à false sur: "
      + variables.allContainers.filter(c,
          c.?securityContext.?allowPrivilegeEscalation.orValue(true) != false
        ).map(c, c.name).join(", ")



apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: restrict-storageclass
spec:
  validationActions: [Audit]
  evaluation:
    background:
      enabled: true
  autogen:
    podControllers:
      enabled: false
  matchConstraints:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values: [blue, shared]
    resourceRules:
    - apiGroups: [""]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [persistentvolumeclaims]
  variables:
  - name: sc
    expression: "object.spec.?storageClassName.orValue('')"
  validations:
  - expression: "variables.sc.matches('^(bnpp-.*|ibm-s3fs-cos)$')"
    messageExpression: >-
      "storageClassName [" + variables.sc + "] non autorisé (bnpp-* ou ibm-s3fs-cos)"
---
apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: restrict-storageclass-sts
spec:
  validationActions: [Audit]
  evaluation:
    background:
      enabled: true
  autogen:
    podControllers:
      enabled: false
  matchConstraints:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values: [blue, shared]
    resourceRules:
    - apiGroups: [apps]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [statefulsets]
  validations:
  - expression: >-
      object.spec.?volumeClaimTemplates.orValue([]).all(v,
        v.spec.?storageClassName.orValue('').matches('^(bnpp-.*|ibm-s3fs-cos)$'))
    message: "volumeClaimTemplates: storageClassName doit être bnpp-* ou ibm-s3fs-cos."



apiVersion: policies.kyverno.io/v1
kind: ValidatingPolicy
metadata:
  name: require-annotations
spec:
  validationActions: [Audit]        # → Deny une fois à zéro violation
  evaluation:
    background:
      enabled: true
  autogen:
    podControllers:
      controllers: []               # annotations exigées sur la ressource elle-même
  matchConstraints:
    namespaceSelector:
      matchExpressions:
      - key: kubernetes.io/metadata.name
        operator: In
        values: [blue, shared]
    resourceRules:
    - apiGroups: [""]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [pods, services]
    - apiGroups: [apps]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [deployments, replicasets, daemonsets, statefulsets]
    - apiGroups: [batch]
      apiVersions: [v1]
      operations: [CREATE, UPDATE]
      resources: [jobs, cronjobs]
  variables:
  - name: annots
    expression: "object.metadata.?annotations.orValue({})"
  - name: env
    expression: "variables.annots[?'com.illumio.env'].orValue('')"
  - name: loc
    expression: "variables.annots[?'com.illumio.com'].orValue('')"
  validations:
  - expression: "variables.env != ''"
    messageExpression: >-
      "annotation 'com.illumio.env' absente sur "
      + object.kind + "/" + object.metadata.name
  - expression: >-
      variables.env == '' || variables.env.matches('E_(PROD|PPROD|INT)$')
    messageExpression: >-
      "annotation 'com.illumio.env' mal formée: [" + variables.env + "] sur "
      + object.kind + "/" + object.metadata.name
      + " (attendu E_PROD, E_PPROD ou E_INT)"
  - expression: >-
      variables.loc == '' || variables.loc.matches('^R(INTRANET|RESTRICTED)$')
    messageExpression: >-
      "annotation 'com.illumio.com' mal formée: [" + variables.loc + "] sur "
      + object.kind + "/" + object.metadata.name
      + " (attendu RINTRANET ou RRESTRICTED)"
