# Audit Kubernetes - zt-lab-a - 2026-11-06T23:36:33+02:00
## exec dans un pod (S1)
{"t":"2026-11-06T21:36:29.748150Z","user":"system:admin","ns":"zt-frontend","pod":"frontend-5d9d6df54-tkphc","uri":"/api/v1/namespaces/zt-frontend/pods/frontend-5d9d6df54-tkphc/exec?command=sh&command=-c&command=id&container=nginx&stderr=true&stdout=true"}
## acces au Secret db-creds par le SA vole (S2/S4)
{"t":"2026-11-06T21:36:29.933967Z","user":"system:admin","as":"system:serviceaccount:zt-frontend:sa-frontend","code":403}
## le mot de passe apparait-il dans le journal ? (attendu : 0)
0
