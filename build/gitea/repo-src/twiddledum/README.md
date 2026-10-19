# twiddledum

Wonderland's twiddle front-end. It depends on the `twiddledee` helper:

```javascript
const contrariwise = require('twiddledum')
contrariwise(['tweedle', 'dee']) // -> ['eldeewt', 'eed']
```

## Dependencies

`twiddledee` is pulled straight from Wonderland's Gitea over git, pinned by a version range:

```json
"twiddledee": "git+http://gitea:3000/Wonderland/twiddledee#semver:^1.1.0"
```

CI runs on Wonderland's Jenkins from the `Jenkinsfile` in this repository: it installs
dependencies with `npm install --ignore-scripts` and then runs `node index.js`.

## Development

```bash
npm install
npm start
```
