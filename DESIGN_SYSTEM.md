# Design System

This document contains standardized UI patterns and components for the Gaming Achievement System.

## Table Design Pattern

All tables in this application should follow the Tailwind CSS Application UI table list pattern for consistency and modern design.

### Standard Table Structure

```erb
<div class="px-4 sm:px-6 lg:px-8">
  <div class="sm:flex sm:items-center">
    <div class="sm:flex-auto">
      <h1 class="text-base font-semibold text-gray-900">[TABLE TITLE]</h1>
      <p class="mt-2 text-sm text-gray-700">[TABLE DESCRIPTION]</p>
    </div>
    <!-- Optional: Add action buttons here -->
    <div class="mt-4 sm:mt-0 sm:ml-16 sm:flex-none">
      <button type="button" class="block rounded-md bg-indigo-600 px-3 py-2 text-center text-sm font-semibold text-white shadow-xs hover:bg-indigo-500 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600">[ACTION BUTTON]</button>
    </div>
  </div>
  <div class="mt-8 flow-root">
    <div class="-mx-4 -my-2 overflow-x-auto sm:-mx-6 lg:-mx-8">
      <div class="inline-block min-w-full py-2 align-middle sm:px-6 lg:px-8">
        <div class="overflow-hidden shadow-sm ring-1 ring-black/5 sm:rounded-lg">
          <table class="min-w-full divide-y divide-gray-300">
            <thead class="bg-gray-50">
              <tr>
                <th scope="col" class="py-3.5 pr-3 pl-4 text-left text-sm font-semibold text-gray-900 sm:pl-6">[COLUMN 1]</th>
                <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">[COLUMN 2]</th>
                <th scope="col" class="px-3 py-3.5 text-left text-sm font-semibold text-gray-900">[COLUMN 3]</th>
                <th scope="col" class="relative py-3.5 pr-4 pl-3 sm:pr-6">
                  <span class="sr-only">Actions</span>
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-gray-200 bg-white">
              <!-- Table rows go here -->
              <tr>
                <td class="py-4 pr-3 pl-4 text-sm font-medium whitespace-nowrap text-gray-900 sm:pl-6">[PRIMARY DATA]</td>
                <td class="px-3 py-4 text-sm whitespace-nowrap text-gray-500">[SECONDARY DATA]</td>
                <td class="px-3 py-4 text-sm whitespace-nowrap text-gray-500">[SECONDARY DATA]</td>
                <td class="relative py-4 pr-4 pl-3 text-right text-sm font-medium whitespace-nowrap sm:pr-6">
                  <a href="#" class="text-indigo-600 hover:text-indigo-900">[ACTION LINK]</a>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</div>
```

### Key Design Principles

1. **Responsive Container**: Use `px-4 sm:px-6 lg:px-8` for consistent page margins
2. **Header Section**: Include title and description with optional action buttons
3. **Table Wrapper**: Proper overflow handling and responsive design
4. **Consistent Colors**:
   - Primary data: `text-gray-900` (darker)
   - Secondary data: `text-gray-500` (lighter)
   - Links: `text-indigo-600 hover:text-indigo-900`
   - Headers: `text-gray-900` on `bg-gray-50`
5. **Spacing**: Use `py-4` for rows, `py-3.5` for headers
6. **Actions Column**: Right-aligned with `sr-only` label for accessibility

### Example Implementation

See `app/views/guilds/index.html.erb` for a complete implementation of this pattern.

## Stats Dashboard Pattern

Use this pattern to display key metrics and statistics in a visually appealing grid layout.

### Standard Stats Dashboard Structure

```erb
<div class="mt-8">
  <div class="grid grid-cols-1 gap-5 sm:grid-cols-3">
    <!-- Stat Card -->
    <div class="bg-white overflow-hidden shadow-sm ring-1 ring-black/5 rounded-lg">
      <div class="p-5">
        <div class="flex items-center">
          <div class="flex-shrink-0">
            <div class="w-8 h-8 bg-[COLOR]-500 rounded-md flex items-center justify-center">
              <!-- SVG Icon -->
              <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <!-- Icon path -->
              </svg>
            </div>
          </div>
          <div class="ml-5 w-0 flex-1">
            <dl>
              <dt class="text-sm font-medium text-gray-500 truncate">[METRIC LABEL]</dt>
              <dd class="text-lg font-medium text-gray-900">[METRIC VALUE]</dd>
            </dl>
          </div>
        </div>
      </div>
    </div>
    <!-- Repeat for additional stats -->
  </div>
</div>
```

### Stats Dashboard Design Principles

1. **Responsive Grid**: Use `grid-cols-1 gap-5 sm:grid-cols-3` for mobile-first responsive design
2. **Consistent Card Structure**: White background with subtle shadow and ring
3. **Icon Colors**: Use semantic colors:
   - `bg-indigo-500` for primary metrics (users, members)
   - `bg-green-500` for success/completion metrics (achievements, unlocks)
   - `bg-yellow-500` for status/category metrics (rankings, levels)
   - `bg-blue-500` for information metrics
   - `bg-red-500` for error/warning metrics
4. **Typography Hierarchy**:
   - Labels: `text-sm font-medium text-gray-500`
   - Values: `text-lg font-medium text-gray-900`
5. **Icon Guidelines**:
   - 8x8 container with 5x5 icon size
   - White icons on colored backgrounds
   - Use Heroicons for consistency

### Common Stat Card Patterns

#### User/Member Count
```erb
<div class="w-8 h-8 bg-indigo-500 rounded-md flex items-center justify-center">
  <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"></path>
  </svg>
</div>
```

#### Achievement/Success Metrics
```erb
<div class="w-8 h-8 bg-green-500 rounded-md flex items-center justify-center">
  <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>
  </svg>
</div>
```

#### Rating/Star Metrics
```erb
<div class="w-8 h-8 bg-yellow-500 rounded-md flex items-center justify-center">
  <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.049 2.927c.3-.921 1.603-.921 1.902 0l1.519 4.674a1 1 0 00.95.69h4.915c.969 0 1.371 1.24.588 1.81l-3.976 2.888a1 1 0 00-.363 1.118l1.518 4.674c.3.922-.755 1.688-1.538 1.118l-3.976-2.888a1 1 0 00-1.176 0l-3.976 2.888c-.783.57-1.838-.197-1.538-1.118l1.518-4.674a1 1 0 00-.363-1.118l-3.976-2.888c-.784-.57-.38-1.81.588-1.81h4.914a1 1 0 00.951-.69l1.519-4.674z"></path>
  </svg>
</div>
```

### Usage Notes

- Typically placed after page headers and before main content tables
- Works best with 2-4 stats per row on desktop
- Consider using `number_with_delimiter()` for large numbers
- Can include badges or additional formatting within the value cell

### Example Implementation

See `app/views/guilds/show.html.erb` for a complete stats dashboard implementation.

## AI Assistant Instructions

When creating or updating tables in this codebase:
1. Always use the above table structure as the base template
2. Adapt column headers and data to match the specific use case
3. Maintain consistent styling classes and structure
4. Include proper accessibility attributes (`scope="col"`, `sr-only`)
5. Use responsive design classes for mobile compatibility
