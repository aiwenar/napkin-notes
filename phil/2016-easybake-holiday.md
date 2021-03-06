# ⛄️ ❄️ 🏂  Advice on holiday work? 🏂 ❄️ ⛄️

Over the holidays I would like to work on adding some features to reduce the amount of explicit state that needs to be kept in one's head when developing recipes (and make it more stateless like CSS is). See [Example](https://github.com/Connexions/cnx-recipes/pull/112/commits/54d56faa4d5dedb3c7474ac6aff9620c994884cc)

Based on patterns I've seen while looking through the existing recipes, the following are features I'm proposing to write (in roughly increasing difficulty):

1. Custom console logging messages (the bare minimum needed for developing in any language)
1. Order-independent attribute modifiers (setting/removing `id/class/data-*` attributes)
1. Implicit pass numbers (using `::after-move` selector)
1. Nested `::outside` and numbered `::before(3)` selectors
1. Source maps for raw and baked HTML files

But before I start digging in the code I was wondering if folks had thoughts/pointers on how to approach these features and whether they thought these would be useful (preferably with the harder ones because they require changes to cssselect2 :smile:).




## Custom console logging messages

```css
div {
  -log: "I am a" "message with" "id=" attr(id);
}
```

Input HTML:
```html
<body>
  <section data-type="chapter">
    <div class="foo" id="id123"/>
  </section>
</body>
```

Console Output:
```
section[data-type="chapter"]>div.foo#id123 : I am amessage withid=id123
```




## Order-independent attribute modifiers

Setting attributes is difficult to reason about when the order that rules are executed
depends on the order they are matched (which is why CSS created selectivity rankings).

This defines the attributes as being idempotent so the order does not matter (& removes cognitive load).

Also, to aid debugging, this method allows an HTML to be opened in the browser and the developer can easily see which declaration will be called even though the browser does not support the declaration (by inspecting the element).

The naming of these is heavily inspired by the existing `counter-reset:` and `string-set:` rules. **Note:** Suffixing each rule with `-set` may be overkill because in CSS most declarations _set_ things (like `font: serif;` `color: blue;`) but it is easily greppable (to replace later, or to fix bugs) and does match nicely with `-remove` and `-add`.

The execution order of the `*-set:`, `*-add:`, `content:`, and `*-remove` declarations are the order listed earlier in this sentence :smile:. This way, you can set several attributes, use them to generate content, and then remove them if they are no longer needed.

<details>
<summary>Click to show Example Input/Output HTML

```css
div {
  /* Inspired by the following declarations that also change state: */

  /* string-set: stringName "value", string2Name "hello " "world"; */
  /* counter-reset: c1 0, c2 0; */
  class-add: "foo", "converted-" attr(data-type);  /* or none (without quotes) to disable */
  class-remove: "unwanted-class";                  /* or none (without quotes) to disable (...) */
  attribute-set: "data-simple" "true";
  attribute-remove: "data-unwanted", "data-type";
  id-set: uuid(); /* Ensures the element contains a uuid. If it already has one then this will error */
  id-set: true; /* generates a new id if one does not already exist. Mostly for debugging. */
}
div[data-href] {
  attribute-remove: "data-unwanted", "data-type", "data-href";
  attribute-set: "href" attr(data-href), "data-complex" "true";
  tag-name-set: "a"; /* or none (without quotes) to disable */
}
```

</summary>


Input HTML:
```html
<body>
  <div data-type="example" class="test unwanted-class"/>
  <div data-type="link" id="link999" data-href="http://cnx.org"/>
  <div data-type="example" data-unwanted="123"/>
</body>
```

Output HTML:
```html
<body>
  <div class="test foo converted-example" id="id123"   data-simple="true" />
  <a   class="foo converted-link"         id="link999" data-complex="true" data-href="http://cnx.org" />
  <div class="foo converted-example"      id="id234"   data-simple="true" />
</body>
```

</details>




## Implicit pass numbers (using `::after-move` selector)

Use `::after-move` to denote rules that need to occur after a move instead of having to create an additional explicit pass (likely similar to how `::deferred` works).

A common use-case of this feature is in numbering elements. Sometimes they need to be numbered before they are moved and sometimes after. By default, they are numbered before the move since vanilla CSS lacks the concept of moving an element.

<details>
<summary>Click to show Example Input/Output HTML

```css
body { counter-reset: c1 1; }

bar { counter-increment: c1 1; }

bar.needs-move { move-to: bucketName; }
bar.needs-move::after-move(bucketName) {
  content: counter(c1);
}

section { content: pending(bucketName); }
```
</summary>

Input HTML:
```html
<body>
  <bar/>
  <bar class="needs-move"/>
  <bar/>
  <bar class="needs-move"/>
  <section/>
</body>
```

Output HTML:
```html
<body>
  <bar/>
  <bar/>
  <section>
    <bar class="needs-move">3</bar>
    <bar class="needs-move">4</bar>
  </section>
</body>
```
</details>







## Nested `::outside` and numbered `::after(3)` selectors

One consequence of not relying on execution order when creating new elements is that these elements need to be selectable somehow. Numbering the `::before` and `::after` pseudoselectors allows this feature (as well as the lesser-used `::outside`).

**Note:** I use "X" to denote that they behave differently
than the existing outside/before selectors.

<details>

<summary>Click to show Example Input/Output HTML

```css
p::outsideX {
  class-add: out1;
}
p::outsideX::outsideX {
  class-add: out2;
}
p::outsideX::outsideX::afterX(1) {
  /* Conceptual Review Questions */
  class-add: out2-before1;
}
p::outsideX::outsideX::afterX(2) {
  /* Homework Problems */
  class-add: out2-before2;
}
```

</summary>

Input HTML:
```html
<body>
  <p/>
</body>
```

Output HTML:
```html
<body>
  <div class="out2">
    <div class="out2-before2"/>
    <div class="out2-before1"/>
    <div class="out1">
      <p/>
    </div>
  </div>
</body>
```

</details>


# Conditionally Create Elements `:has-pending(bucketName)`

Currently we create end-of-chapter/book Pages for each book. But sometimes a chapter is missing one of these items (like no "Homework" problems for a chapter). This adds a selector to match only when a bucket is non-empty.

<details>

<summary>Click to show Example Input/Output HTML

```css
.homework-problem { move-to: homeworkBucket; }

.chapter::afterX(1):has-pending(homeworkBucket)::before { content: "Homework Problems"; }
.chapter::afterX(1):has-pending(homeworkBucket)         { content: pending(homeworkBucket); }
```

</summary>

Input HTML:
```html
<body>
  <div class="chapter">
    <p class="homework-problem">What is 2+2?</p>
    <p>Hello chapter with homework</p>
  </div>
  <div class="chapter">
    <p>Hello chapter without homework</p>
  </div>
</body>
```

Output HTML:
```html
<body>
  <div class="chapter">
    <p>Hello chapter with homework</p>
    <div>
      <div>Homework Problems</div>
      <p class="homework-problem">What is 2+2?</p>
    </div>
  </div>
  <div class="chapter">
    <p>Hello chapter without homework</p>
  </div>
</body>
```

</details>


# Source maps for raw and baked HTML files

When a validation error occurs after baking a book it is difficult to find where in the initial Page the problem occurred.

This would generate a source map file (equivalent to a Symbol Table for compiled programs) that would accompany both the Raw HTML file and the Baked HTML file so tools can refer to the _original_ place in HTML where the error occured.

One example of this is broken inter-module links. It is sometimes not known until the end of the baking process that a link is invalid. This would help find the original source of the broken link.

If a piece of HTML was injected as part of baking, the source map could even point to the CSS where it occurred.
