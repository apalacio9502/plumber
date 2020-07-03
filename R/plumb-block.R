
# TODO: delete once we require R 3.3.0
trimws <- function(string){
  string <- gsub("^\\s+", "", string)
  gsub("\\s+$", "", string)
}

stopOnLine <- function(lineNum, line, msg){
  stop("Error on line #", lineNum, ": '", line, "' - ", msg)
}

#' @param lineNum The line number just above the function we're documenting
#' @param file A character vector representing all the lines in the file
#' @noRd
plumbBlock <- function(lineNum, file){
  paths <- NULL
  preempt <- NULL
  filter <- NULL
  image <- NULL
  imageAttr <- NULL
  serializer <- NULL
  assets <- NULL
  params <- NULL
  comments <- ""
  responses <- NULL
  tags <- NULL
  routerModifier <- NULL
  while (lineNum > 0 && (stri_detect_regex(file[lineNum], pattern="^#['\\*]") || stri_trim_both(file[lineNum]) == "")){

    line <- file[lineNum]

    epMat <- stri_match(line, regex="^#['\\*]\\s*@(get|put|post|use|delete|head|options|patch)(\\s+(.*)$)?")
    if (!is.na(epMat[1,2])){
      p <- stri_trim_both(epMat[1,4])

      if (is.na(p) || p == ""){
        stopOnLine(lineNum, line, "No path specified.")
      }

      if (is.null(paths)){
        paths <- list()
      }

      paths[[length(paths)+1]] <- list(verb = enumerateVerbs(epMat[1,2]), path = p)
    }

    filterMat <- stri_match(line, regex="^#['\\*]\\s*@filter(\\s+(.*)$)?")
    if (!is.na(filterMat[1,1])){
      f <- stri_trim_both(filterMat[1,3])

      if (is.na(f) || f == ""){
        stopOnLine(lineNum, line, "No @filter name specified.")
      }

      if (!is.null(filter)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple @filters specified for one function.")
      }

      filter <- f
    }

    preemptMat <- stri_match(line, regex="^#['\\*]\\s*@preempt(\\s+(.*)\\s*$)?")
    if (!is.na(preemptMat[1,1])){
      p <- stri_trim_both(preemptMat[1,3])
      if (is.na(p) || p == ""){
        stopOnLine(lineNum, line, "No @preempt specified")
      }
      if (!is.null(preempt)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple @preempts specified for one function.")
      }
      preempt <- p
    }

    assetsMat <- stri_match(line, regex="^#['\\*]\\s*@assets(\\s+(\\S*)(\\s+(\\S+))?\\s*)?$")
    if (!is.na(assetsMat[1,1])){
      dir <- stri_trim_both(assetsMat[1,3])
      if (is.na(dir) || dir == ""){
        stopOnLine(lineNum, line, "No directory specified for @assets")
      }
      prefixPath <- stri_trim_both(assetsMat[1,5])
      if (is.na(prefixPath) || prefixPath == ""){
        prefixPath <- "/public"
      }
      if (!is.null(assets)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple @assets specified for one entity.")
      }
      assets <- list(dir=dir, path=prefixPath)
    }

    serMat <- stri_match(line, regex="^#['\\*]\\s*@serializer(\\s+([^\\s]+)\\s*(.*)\\s*$)?")
    if (!is.na(serMat[1,1])){
      s <- stri_trim_both(serMat[1,3])
      if (is.na(s) || s == ""){
        stopOnLine(lineNum, line, "No @serializer specified")
      }
      if (!is.null(serializer)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple @serializers specified for one function.")
      }

      if (!s %in% names(.globals$serializers)){
        stop("No such @serializer registered: ", s)
      }

      ser <- .globals$serializers[[s]]

      if (!is.na(serMat[1, 4]) && serMat[1,4] != ""){
        # We have an arg to pass in to the serializer
        argList <- eval(parse(text=serMat[1,4]))
      } else {
        argList <- list()
      }
      tryCatch({
        serializer <- do.call(ser, argList)
      }, error = function(e) {
        stopOnLine(lineNum, line, paste0("Error creating serializer: ", s, "\n", e))
      })

    }

    shortSerMat <- stri_match(line, regex="^#['\\*]\\s*@(json|html)(.*)$")
    if (!is.na(shortSerMat[1,2])) {
      s <- stri_trim_both(shortSerMat[1,2])
      if (!is.null(serializer)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple @serializers specified for one function (shorthand serializers like @json count, too).")
      }

      if (!is.na(s) && !s %in% names(.globals$serializers)){
        stop("No such @serializer registered: ", s)
      }
      shortSerAttr <- trimws(shortSerMat[1,3])
      if(!identical(shortSerAttr, "") && !grepl("^\\(.*\\)$", shortSerAttr)){
        stopOnLine(lineNum, line, paste0("Supplemental arguments to the serializer must be surrounded by parentheses, as in `#' @", s, "(na='null')`"))
      }

      if (shortSerAttr != "") {
        # We have an arg to pass in to the serializer
        argList <- eval(parse(text=paste0("list", shortSerAttr)))
      } else {
        argList <- list()
      }
      tryCatch({
        serializer <- do.call(.globals$serializers[[s]], argList)
      }, error = function(e) {
        stopOnLine(lineNum, line, paste0("Error creating serializer: ", s, "\n", e))
      })

    }

    imageMat <- stri_match(line, regex="^#['\\*]\\s*@(jpeg|png|svg)([\\s\\(].*)?\\s*$")
    if (!is.na(imageMat[1,1])){
      if (!is.null(image)){
        # Must have already assigned.
        stopOnLine(lineNum, line, "Multiple image annotations on one function.")
      }
      image <- imageMat[1,2]

      imageAttr <- trimws(imageMat[1,3])
      if (is.na(imageAttr)){
        imageAttr <- ""
      }
      if(!identical(imageAttr, "") && !grepl("^\\(.*\\)$", imageAttr, perl=TRUE)){
        stopOnLine(lineNum, line, "Supplemental arguments to the image serializer must be surrounded by parentheses, as in `#' @png (width=200)`")
      }
    }

    responseMat <- stri_match(line, regex="^#['\\*]\\s*@response\\s+(\\w+)\\s+(\\S.+)\\s*$")
    if (!is.na(responseMat[1,1])){
      resp <- list()
      resp[[responseMat[1,2]]] <- list(description=responseMat[1,3])
      responses <- c(responses, resp)
    }

    paramMat <- stri_match(line, regex="^#['\\*]\\s*@param(\\s+([^\\s:]+):?([^\\s*]+)?(\\*)?(?:\\s+(.*))?\\s*$)?")
    if (!is.na(paramMat[1,2])){
      name <- paramMat[1,3]
      if (is.na(name)){
        stopOnLine(lineNum, line, "No parameter specified.")
      }
      plumberType <- stri_replace_all(paramMat[1,4], "$1", regex = "^\\[([^\\]]*)\\]$")
      apiType <- plumberToApiType(plumberType)
      isArray <- stri_detect_regex(paramMat[1,4], "^\\[[^\\]]*\\]$")
      isArray <- isArray && apiType %in% filterApiTypes(TRUE, "arraySupport")
      isArray[is.na(isArray)] <- defaultIsArray
      required <- identical(paramMat[1,5], "*")

      params[[name]] <- list(desc=paramMat[1,6], type=apiType, required=required, isArray=isArray)
    }

    tagMat <- stri_match(line, regex="^#['\\*]\\s*@tag\\s+(\\S.+)\\s*")
    if (!is.na(tagMat[1,1])){
      t <- stri_trim_both(tagMat[1,2])
      if (is.na(t) || t == ""){
        stopOnLine(lineNum, line, "No tag specified.")
      }
      if (t %in% tags){
        stopOnLine(lineNum, line, "Duplicate tag specified.")
      }
      tags <- c(tags, t)
    }

    commentMat <- stri_match(line, regex="^#['\\*]\\s*([^@\\s].*$)")
    if (!is.na(commentMat[1,2])){
      comments <- paste(comments, commentMat[1,2])
    }

    routerModifierMat <- stri_match(line, regex="^#['\\*]\\s*@plumber")
    if (!is.na(routerModifierMat[1,1])) {
      routerModifier <- TRUE
    }

    lineNum <- lineNum - 1
  }

  list(
    paths = paths,
    preempt = preempt,
    filter = filter,
    image = image,
    imageAttr = imageAttr,
    serializer = serializer,
    assets = assets,
    params = rev(params),
    comments = comments,
    responses = responses,
    tags = tags,
    routerModifier = routerModifier
  )
}

#' Evaluate and activate a "block" of code found in a plumber API file.
#' @include images.R
#' @noRd
evaluateBlock <- function(srcref, file, expr, envir, addEndpoint, addFilter, pr) {
  lineNum <- srcref[1] - 1

  block <- plumbBlock(lineNum, file)

  if (sum(!is.null(block$filter), !is.null(block$paths), !is.null(block$assets), !is.null(block$routerModifier)) > 1){
    stopOnLine(lineNum, file[lineNum], "A single function can only be a filter, an API endpoint, an asset or a router modifier (@filter AND @get, @post, @assets, @plumber, etc.)")
  }

  # ALL if statements possibilities must eventually call eval(expr, envir)
  if (!is.null(block$paths)){
    lapply(block$paths, function(p){
      ep <- PlumberEndpoint$new(p$verb, p$path, expr, envir, block$serializer, srcref, block$params, block$comments, block$responses, block$tags)

      if (!is.null(block$image)){
        # Arguments to pass in to the image serializer
        imageArgs <- NULL
        if (!identical(block$imageAttr, "")){
          call <- paste("list", block$imageAttr)
          imageArgs <- eval(parse(text=call))
        }

        if (block$image == "png"){
          ep$registerHooks(render_png(imageArgs))
          ep$serializer <- serializer_content_type("image/png")
        } else if (block$image == "jpeg"){
          ep$registerHooks(render_jpeg(imageArgs))
          ep$serializer <- serializer_content_type("image/jpeg")
        } else if (block$image == "svg"){
          ep$registerHooks(render_svg(imageArgs))
          ep$serializer <- serializer_content_type("image/svg+xml")
        } else {
          stop("Image format not found: ", block$image)
        }
      }

      addEndpoint(ep, block$preempt)
    })
  } else if (!is.null(block$filter)){
    filter <- PlumberFilter$new(block$filter, expr, envir, block$serializer, srcref)
    addFilter(filter)

  } else if (!is.null(block$assets)){
    path <- block$assets$path

    # Leading slash
    if (substr(path, 1,1) != "/"){
      path <- paste0("/", path)
    }

    stat <- PlumberStatic$new(block$assets$dir, expr)
    pr$mount(path, stat)

  } else if (!is.null(block$routerModifier)) {
    if (is.expression(expr)){
      func <- eval(expr, envir)
      if (is.function(func)) {
        func(pr)
        return()
      }
    }
    stopOnLine(lineNum, file[lineNum], "Invalid expression for @plumber tag, please use the form `function(pr) { }`.")
  } else {
    eval(expr, envir)
  }
}