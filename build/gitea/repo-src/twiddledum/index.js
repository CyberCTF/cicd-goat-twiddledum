'use strict'

// Twiddledum — pairs up with Twiddledee. "I know what you're thinking about," said Tweedledum,
// "but it isn't so, nohow." The app leans on the twiddledee helper for its one trick; requiring the
// dependency runs the dependency's module code, which is the whole point of the CI build below.
const twiddle = require('twiddledee')

function contrariwise (items) {
  return (items || []).map(function (item) { return twiddle(item) })
}

console.log('twiddledum ready:', contrariwise(['tweedle', 'dee', 'dum']).join(', '))

module.exports = contrariwise
