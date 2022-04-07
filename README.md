<!--
  Licensed to ObjectStyle LLC under one
  or more contributor license agreements.  See the NOTICE file
  distributed with this work for additional information
  regarding copyright ownership.  The ObjectStyle LLC licenses
  this file to you under the Apache License, Version 2.0 (the
  "License"); you may not use this file except in compliance
  with the License.  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing,
  software distributed under the License is distributed on an
  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
  KIND, either express or implied.  See the License for the
  specific language governing permissions and limitations
  under the License.
  -->

[![build test deploy](https://github.com/bootique/bootique-modules-parent/actions/workflows/maven.yml/badge.svg)](https://github.com/bootique/bootique-modules-parent/actions/workflows/maven.yml)
[![Maven Central](https://img.shields.io/maven-central/v/io.bootique.modules.parent/bootique-modules-parent.svg?colorB=brightgreen)](https://search.maven.org/artifact/io.bootique.modules.parent/bootique-modules-parent/)

_Not for public use!_

A parent POM of [Bootique](http://bootique.io) standard modules. Stores common development and deployment settings, 
and common dependency versions. 

Downstream Bootique modules should use `bootique-modules-parent` with a matching major version (e.g. 
`bootique-modules-parent:3.0.7` can be used by 3.x Bootique modules). Minor versions intentionally do not match, as 
`bootique-modules-parent` is released independently of other modules to facilitate the development process for the rest 
of the framework.
