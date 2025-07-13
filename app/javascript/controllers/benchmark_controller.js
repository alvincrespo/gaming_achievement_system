import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "results", "content", "template", "errorTemplate",
                   "windowTime", "windowCount", "joinTime", "joinCount",
                   "joinRecords", "joinError", "speedupAlert", "speedupValue"]
  static values = { url: String }

  async runBenchmark() {
    this.setLoadingState()

    try {
      const response = await fetch(this.urlValue, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]').content,
          'Content-Type': 'application/json'
        }
      })

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
  }

  resetButtonState() {
    this.buttonTarget.disabled = false
    this.buttonTarget.textContent = 'Run Performance Benchmark'
  }

  displayResults(data) {
    // Clone the template
    const template = this.templateTarget.content.cloneNode(true)

    // Populate template with data
    template.querySelector('[data-benchmark-target="windowTime"]').textContent = `${data.window_function.toFixed(3)}s`
    template.querySelector('[data-benchmark-target="windowCount"]').textContent = data.window_function_count
    template.querySelector('[data-benchmark-target="joinTime"]').textContent = `${data.join.toFixed(3)}s`

    // Handle join results or error
    if (data.join_error) {
      template.querySelector('[data-benchmark-target="joinRecords"]').style.display = 'none'
      const joinError = template.querySelector('[data-benchmark-target="joinError"]')
      joinError.textContent = data.join_error
      joinError.style.display = 'block'
    } else {
      template.querySelector('[data-benchmark-target="joinCount"]').textContent = data.join_count
    }

    // Show speedup if available
    if (data.speedup) {
      const speedupAlert = template.querySelector('[data-benchmark-target="speedupAlert"]')
      speedupAlert.querySelector('[data-benchmark-target="speedupValue"]').textContent = `${data.speedup}x`
      speedupAlert.style.display = 'block'
    }

    // Replace content and show results
    this.contentTarget.innerHTML = ''
    this.contentTarget.appendChild(template)
    this.resultsTarget.style.display = 'block'
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
