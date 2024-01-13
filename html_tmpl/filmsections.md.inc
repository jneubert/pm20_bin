<a id="filmsections" />
<tmpl_loop filming_loop>
## <tmpl_var filming_title>

<p><tmpl_var legal></p>

<tmpl_if is_de>
<p>Gesamtzahl der Mikrofilmaufnahmen: <tmpl_if total_number_of_images><tmpl_var total_number_of_images><tmpl_else>unbekannt - auffindbar derzeit nur über die [Filmliste](<tmpl_var filmlist_link>).</tmpl_if></p>
</tmpl_if is_de>
<tmpl_if is_en>
<p>Total number of images: <tmpl_if total_number_of_images><tmpl_var total_number_of_images><tmpl_else>unknown - currently only discoverable via the [film list](<tmpl_var filmlist_link>).</tmpl_if></p>
</tmpl_if is_en>

<tmpl_if filmsection_loop>

::: {.sectiontable}

 | 
----|-------
<tmpl_loop filmsection_loop><a class="btn" href="<tmpl_var filmviewer_url>" rel="nofollow"><tmpl_if is_de>Bilder auf Film </tmpl_if><tmpl_if is_en>Images on film </tmpl_if><tmpl_var film_id></a> | <tmpl_if first_img><tmpl_var first_img></tmpl_if>
</tmpl_loop filmsection_loop>

:::

</tmpl_if filmsection_loop>

</tmpl_loop filming_loop>

