apiVersion: v1
kind: Pod
metadata:
  name: __POD_NAME__
  labels:
    dev.ncrmro.agent.kind: nix-zellij
    dev.ncrmro.agent.workspace-slug: __WORKSPACE_SLUG__
  annotations:
    dev.ncrmro.agent.workspace: __WORKSPACE_Q__
    dev.ncrmro.agent.config-hash: __CONFIG_HASH__
spec:
  restartPolicy: Never
  containers:
    - name: __CONTAINER_NAME__
      image: __IMAGE_REF__
      imagePullPolicy: Never
      command: ["/bin/bash", "-lc", "chmod 1777 /tmp && exec sleep infinity"]
      workingDir: __WORKSPACE_Q__
      volumeMounts:
        - name: workspace
          mountPath: __WORKSPACE_Q__
        - name: outfitter-root
          mountPath: /root/.outfitter
        - name: pi-home
          mountPath: /root/.pi
          readOnly: true
        - name: tmp
          mountPath: /tmp
__GITHUB_TOKEN_VOLUME_MOUNT__
  volumes:
    - name: workspace
      hostPath:
        path: __WORKSPACE_Q__
        type: Directory
    - name: outfitter-root
      hostPath:
        path: __OUTFITTER_ROOT_DIR_Q__
        type: Directory
    - name: pi-home
      hostPath:
        path: __PI_HOME_DIR_Q__
        type: Directory
    - name: tmp
      persistentVolumeClaim:
        claimName: __TMP_VOLUME_NAME__
__GITHUB_TOKEN_VOLUME__
