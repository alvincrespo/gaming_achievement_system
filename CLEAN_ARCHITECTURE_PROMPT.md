# Clean Architecture Prompt for Dynamic UI Templates

## The Challenge
I need to create a benchmark comparison feature that displays results with dynamic styling based on which approach performs better. The styling should be applied based on actual performance results, not assumptions.

## Requirements

### 1. Template Structure
- Create **two reusable partials**: `_winner.html.erb` and `_loser.html.erb`
- Each partial should have **pre-styled success/failure states**:
  - Winner: Green background, checkmark icon, green text
  - Loser: Red background, X icon, red text
- Use **semantic data targets** for JavaScript population:
  - `data-benchmark-target="winnerTitle"` / `data-benchmark-target="loserTitle"`
  - `data-benchmark-target="winnerTime"` / `data-benchmark-target="loserTime"`
  - `data-benchmark-target="winnerCount"` / `data-benchmark-target="loserCount"`

### 2. Main Template
- Include **one template** that renders both partials
- Template should be populated by JavaScript based on API response
- Keep all styling in the ERB partials, not in JavaScript

### 3. API Structure
Transform the backend to return a **normalized winner/loser structure**:
```json
{
  "guild_id": 123,
  "winner": {
    "count": 1500,
    "execution_time": 0.025,
    "type": "Window Function"
  },
  "loser": {
    "count": 1500,
    "execution_time": 0.240,
    "type": "JOIN"
  },
  "speedup": 9.6
}
```

### 4. JavaScript Logic
- **Determine winner/loser** in the backend, not frontend
- JavaScript should only **populate data**, not apply styling
- Use **semantic data mapping**:
  - `winner.type` → `winnerTitle`
  - `winner.execution_time` → `winnerTime`
  - `winner.count` → `winnerCount`
  - Same pattern for loser

### 5. Architecture Principles
- **Separation of Concerns**: HTML/CSS in templates, logic in backend
- **DRY**: No template duplication - one winner, one loser partial
- **Semantic**: Clear winner/loser structure regardless of which approach wins
- **Maintainable**: Easy to modify styling without touching JavaScript

## Expected File Structure
```
app/views/guilds/
├── _winner.html.erb          # Green success styling with data targets
├── _loser.html.erb           # Red failure styling with data targets
└── compare_queries.html.erb  # Main template using both partials

app/javascript/controllers/
└── benchmark_controller.js   # Simple data population logic

app/services/
└── achievement_query_strategy.rb  # Returns winner/loser JSON structure
```

## Key Success Criteria
1. ✅ **No styling logic in JavaScript**
2. ✅ **Pre-styled partials handle all visual states**
3. ✅ **Backend determines winner/loser**
4. ✅ **Single template handles all scenarios**
5. ✅ **Easy to maintain and extend**

## Anti-Patterns to Avoid
- ❌ Multiple templates for different scenarios
- ❌ JavaScript applying CSS classes or styles
- ❌ Frontend logic determining winner/loser
- ❌ Hardcoded assumptions about which approach wins
- ❌ Template duplication with inverse styling

This approach ensures clean separation of concerns, eliminates duplication, and makes the system easy to maintain and extend.
