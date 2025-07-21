import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "results", "resultsList", "resultItemTemplate", "resultsWrapperTemplate", "resultsTemplate", "errorTemplate"]
  static values = { url: String }

  async runBenchmark() {
    // Prevent multiple concurrent requests
    if (this.buttonTarget.disabled) {
      return
    }

    this.setLoadingState()

    try {
      const response = await fetch(this.urlValue, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`)
      }

      const data = await response.json()
      this.displayResults(data)
    } catch (error) {
      console.error('Benchmark failed:', error)
      this.displayError('Failed to run benchmark. Please try again.')
    } finally {
      this.resetButtonState()
    }
  }

  setLoadingState() {
    this.buttonTarget.disabled = true
    this.buttonTarget.textContent = 'Running benchmark...'
    this.buttonTarget.classList.add('opacity-75', 'cursor-not-allowed')
  }

  resetButtonState() {
    this.buttonTarget.disabled = false
    this.buttonTarget.textContent = 'Run Performance Benchmark'
    this.buttonTarget.classList.remove('opacity-75', 'cursor-not-allowed')
  }

  displayResults(data) {
    // Clone the results template
    const template = this.resultsTemplateTarget.content.cloneNode(true)

    // Populate winner data
    template.querySelector('[data-benchmark-target="winnerTitle"]').textContent = `${data.winner.type} Approach`
    template.querySelector('[data-benchmark-target="winnerTime"]').textContent = `${data.winner.execution_time.toFixed(3)}s`
    template.querySelector('[data-benchmark-target="winnerCount"]').textContent = data.winner.count.toLocaleString()

    // Populate loser data
    template.querySelector('[data-benchmark-target="loserTitle"]').textContent = `${data.loser.type} Approach`
    template.querySelector('[data-benchmark-target="loserTime"]').textContent = `${data.loser.execution_time.toFixed(3)}s`
    template.querySelector('[data-benchmark-target="loserCount"]').textContent = data.loser.count.toLocaleString()

    // Set the speedup message with timestamp for freshness indicator
    const now = new Date().toLocaleTimeString()
    const speedupMessage = `${data.winner.type} approach is <strong>${data.speedup}x</strong> faster than the ${data.loser.type} approach. <em>(Run at ${now})</em>`
    template.querySelector('[data-benchmark-target="speedupMessage"]').innerHTML = speedupMessage

    const resultItemTemplate = this.resultItemTemplateTarget.content.cloneNode(true)
    resultItemTemplate.querySelector('[data-benchmark-target="content"]').appendChild(template)

    // Replace content and show results with a fresh state
    this.resultsListTarget.appendChild(resultItemTemplate)
    this.resultsTarget.removeAttribute('style')

    // Scroll to results for better UX on subsequent runs
    window.scrollTo({
      top: document.body.scrollHeight,
      behavior: 'smooth'
    })
  }

  displayError(message) {
    // Clone the error template
    const errorTemplate = this.errorTemplateTarget.content.cloneNode(true)

    // Populate with error message
    errorTemplate.querySelector('[data-benchmark-target="errorMessage"]').textContent = message

    // Replace content and show results
    this.contentTarget.innerHTML = ''
    this.contentTarget.appendChild(errorTemplate)
    this.resultsTarget.style.display = 'block'
  }
}
