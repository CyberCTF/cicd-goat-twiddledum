'use strict'

// Twiddledee — Wonderland's little twiddle helper. "Contrariwise," continued Tweedledee,
// "if it was so, it might be; and if it were so, it would be; but as it isn't, it ain't."
// Consumers `require('twiddledee')` and call the exported function.
module.exports = function twiddle (value) {
  return String(value).split('').reverse().join('')
}
