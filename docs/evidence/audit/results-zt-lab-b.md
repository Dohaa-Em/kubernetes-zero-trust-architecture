# Audit Kubernetes - zt-lab-b - 2026-11-06T19:58:33+01:00
## exec dans un pod (S1)
{"t":"2026-11-06T18:58:27.587942Z","user":"system:admin","ns":"zt-frontend","pod":"frontend-58d99b4d48-hzvxd","uri":"/api/v1/namespaces/zt-frontend/pods/frontend-58d99b4d48-hzvxd/exec?command=sh&command=-c&command=id&container=nginx&stderr=true&stdout=true"}
{"t":"2026-11-06T18:58:27.587942Z","user":"system:admin","ns":"zt-frontend","pod":"frontend-58d99b4d48-hzvxd","uri":"/api/v1/namespaces/zt-frontend/pods/frontend-58d99b4d48-hzvxd/exec?command=sh&command=-c&command=id&container=nginx&stderr=true&stdout=true"}
## accès au Secret db-creds (S2/S4)
{"t":"2026-11-06T18:57:15.166008Z","user":"system:node:zt-lab-b","as":null,"verb":"watch","code":200}
{"t":"2026-11-06T18:57:47.203155Z","user":"system:serviceaccount:external-secrets:external-secrets","as":null,"verb":"get","code":200}
{"t":"2026-11-06T18:57:15.166008Z","user":"system:node:zt-lab-b","as":null,"verb":"watch","code":200}
{"t":"2026-11-06T18:58:28.348616Z","user":"system:admin","as":"system:serviceaccount:zt-frontend:sa-frontend","verb":"get","code":403}
## le mot de passe apparaît-il dans le journal ? (attendu : 0)
0
