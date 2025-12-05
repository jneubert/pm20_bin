<a id="filmsections" />
<tmpl_loop filming_loop>
### <tmpl_var filming_title>

<p><tmpl_var legal></p>

<tmpl_if is_de>
<p>Gesamtzahl der Mikrofilmaufnahmen: <tmpl_if total_number_of_images><tmpl_var total_number_of_images><tmpl_else>unbekannt - derzeit ggf. auffindbar nur über die [Filmliste](<tmpl_var filmlist_link>).</tmpl_if></p>
</tmpl_if is_de>
<tmpl_if is_en>
<p>Total number of images: <tmpl_if total_number_of_images><tmpl_var total_number_of_images><tmpl_else>unknown - currently only findable via the [film list](<tmpl_var filmlist_link>).</tmpl_if></p>
</tmpl_if is_en>

<tmpl_if filmsection_loop>

::: {.sectiontable}

 | 
--|-------
<tmpl_loop filmsection_loop><a class="btn" href="<tmpl_var filmviewer_url>" rel="nofollow"><tmpl_var section_id></a> | <tmpl_if section_label><tmpl_var section_label></tmpl_if> &#160; <tmpl_if image_count>[(<tmpl_var image_count> <tmpl_if is_de>Aufnahmen</tmpl_if><tmpl_if is_en>images</tmpl_if>)]{.hint}</tmpl_if>
</tmpl_loop filmsection_loop>

:::

</tmpl_if filmsection_loop>

</tmpl_loop filming_loop>

