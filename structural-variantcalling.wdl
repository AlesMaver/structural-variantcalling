version 1.0

# MIT License
#
# Copyright (c) 2018 Leiden University Medical Center
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/bcftools.wdl" as bcftools
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/bwa.wdl" as bwa
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/clever.wdl" as clever
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/common.wdl" as common
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/delly.wdl" as delly
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/duphold.wdl" as duphold
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/gridss.wdl" as gridssTasks
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/manta.wdl" as manta
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/picard.wdl" as picard
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/samtools.wdl" as samtools
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/smoove.wdl" as smoove
import "https://raw.githubusercontent.com/biowdl/tasks/c4b13ec67b0a4c293fa4ef58361e1516d5756270/survivor.wdl" as survivor

workflow SVcalling {
    input {
        File bamFile
        File bamIndex
        File referenceFasta
        File referenceFastaFai
        File referenceFastaDict
        BwaIndex bwaIndex
        String sample
        Array[String] svtypes = ["DEL", "DUP", "INS", "INV", "BND"]
        Boolean excludeMisHomRef = false
        Boolean runDupHold = false
        Boolean runSmoove = true
        String outputDir = "."
        Map[String, String] dockerImages = {
            "bcftools": "quay.io/biocontainers/bcftools:1.10.2--h4f4756c_2",
            "clever": "quay.io/biowdl/clever-toolkit:2.4",
            "delly": "quay.io/biocontainers/delly:0.8.5--hf3ca161_0",
            "manta": "quay.io/biocontainers/manta:1.4.0--py27_1",
            "picard":"quay.io/biocontainers/picard:2.23.2--0",
            "samtools": "quay.io/biocontainers/samtools:1.10--h9402c20_2",
            "survivor": "quay.io/biocontainers/survivor:1.0.6--h6bb024c_0",
            "smoove": "quay.io/biocontainers/smoove:0.2.5--0",
            "duphold": "quay.io/biocontainers/duphold:0.2.1--h516909a_1",
            "gridss": "quay.io/biowdl/gridss:2.12.2"
        }
    }

    meta {allowNestedInputs: true}

    String SVdir = outputDir + '/structural-variants/'
	
    if (runSmoove) {
        call smoove.Call as smoove {
            input:
                dockerImage = dockerImages["smoove"],
                bamFile = bamFile,
                bamIndex = bamIndex,
                referenceFasta = referenceFasta,
                referenceFastaFai = referenceFastaFai,
                sample = sample,
                outputDir = SVdir + 'smoove'
        }

        Pair[File, String] smooveVcfAndCaller = (smoove.smooveVcf, "smoove")
    }

    call delly.CallSV as delly {
        input:
            dockerImage = dockerImages["delly"],
            bamFile = bamFile,
            bamIndex = bamIndex,
            referenceFasta = referenceFasta,
            referenceFastaFai = referenceFastaFai,
            outputPath = SVdir + 'delly/' + sample + ".delly.bcf"
    }   

    call bcftools.View as delly2vcf {
        input:
            dockerImage = dockerImages["bcftools"],
            inputFile = delly.dellyBcf,
            outputPath = SVdir + 'delly/' + sample + ".delly.vcf"
    } 

    call clever.Prediction as clever {
        input:
            dockerImage = dockerImages["clever"],
            bamFile = bamFile,
            bamIndex = bamIndex,
            bwaIndex = bwaIndex,
            outputPath = SVdir + 'clever/'
    } 
    
    call samtools.FilterShortReadsBam {
        input:
            dockerImage = dockerImages["samtools"],
            bamFile = bamFile,
            outputPathBam = SVdir + 'filteredBam/' + sample + ".filtered.bam"
    }

    call clever.Mateclever as mateclever {
        input:
            dockerImage = dockerImages["clever"],
            fiteredBam = FilterShortReadsBam.filteredBam,
            indexedFiteredBam = FilterShortReadsBam.filteredBamIndex,
            bwaIndex = bwaIndex,
            predictions = clever.predictions,
            outputPath = SVdir + 'mateclever/'
    }

    call manta.Germline as manta {
        input:
            dockerImage = dockerImages["manta"],
            bamFile = bamFile,
            bamIndex = bamIndex,
            referenceFasta = referenceFasta,
            referenceFastaFai = referenceFastaFai,
            runDir = SVdir + 'manta/'
    }

    call gridssTasks.GRIDSS as gridss {
        input:
            dockerImage = dockerImages["gridss"],
            tumorBam = bamFile,
            tumorBai = bamIndex,
            tumorLabel = sample,
            reference = bwaIndex,
            outputPrefix = SVdir + "gridss/~{sample}.gridss"
    }

    call gridssTasks.AnnotateSvTypes as gridssSvTyped {
        input:
            gridssVcf = gridss.vcf,
            gridssVcfIndex = gridss.vcfIndex,
            outputPath = SVdir + "gridss/~{sample}.gridss.svtyped.vcf.bgz"
    }

    Array[Pair[File,String]] vcfAndCaller = select_all([(delly2vcf.outputVcf, "delly"),
        (manta.mantaVCF, "manta"), (mateclever.matecleverVcf, "clever"), smooveVcfAndCaller,
        (gridssSvTyped.vcf, "gridss")])

    scatter (svtype in svtypes) {
         scatter (pair in vcfAndCaller) {
            String prefix = SVdir + pair.right + '/' + svtype

            call bcftools.View as getSVtype {
                input:
                    dockerImage = dockerImages["bcftools"],
                    inputFile = pair.left,
                    outputPath = prefix + '.vcf',
                    include = "'SVTYPE=\"${svtype}\"'"
            }

            call picard.RenameSample as renameSample {
                input:
                    dockerImage = dockerImages["picard"],
                    inputVcf = getSVtype.outputVcf,
                    outputPath =  prefix + '.renamed.vcf',
                    newSampleName = pair.right
            }

            call bcftools.Sort as sort {
                input:
                    dockerImage = dockerImages["bcftools"],
                    inputFile = renameSample.renamedVcf,
                    outputPath = prefix + '.sorted.vcf',
                    tmpDir = SVdir + 'tmp-' + sample + "." + svtype + "." + pair.right
            }

            call bcftools.Annotate as setId {
                input:
                    dockerImage = dockerImages["bcftools"],
                    inputFile = sort.outputVcf,
                    outputPath = prefix + '.changed_id.vcf',
                    newId = "'${pair.right}\\_%CHROM\\_%POS\\_%END'"
            }

            if (runDupHold) {
                call duphold.Duphold as annotateDH {
                    input:
                        dockerImage = dockerImages["duphold"],
                        inputVcf = setId.outputVcf,
                        bamFile = bamFile,
                        bamIndex = bamIndex,
                        referenceFasta = referenceFasta,
                        referenceFastaFai = referenceFastaFai,
                        outputPath = prefix + '.duphold.vcf',
                        sample = pair.right
                }

                call bcftools.View as removeFpDupDel {
                    input:
                        dockerImage = dockerImages["bcftools"],
                        inputFile = annotateDH.outputVcf,
                        outputPath = prefix + '.duphold_filtered.vcf',
                        include = "'(SVTYPE = \"DEL\" & FMT/DHFFC[0] < 0.7) | (SVTYPE = \"DUP\" & FMT/DHBFC[0] > 1.3)'"
                }
            }

            if (excludeMisHomRef) {
                call bcftools.View as removeMisHomRR {
                    input:
                    dockerImage = dockerImages["bcftools"],
                    inputFile = select_first([removeFpDupDel.outputVcf, setId.outputVcf]),
                    outputPath = prefix + '.GT_filtered.vcf',
                    excludeUncalled = true,
                    exclude = "'GT=\"RR\"'"
                }
            }

            File toBeMergedVcfs = select_first([removeMisHomRR.outputVcf, removeFpDupDel.outputVcf, setId.outputVcf])
         }

        call survivor.Merge as survivor {
            input:
                dockerImage = dockerImages["survivor"],
                filePaths = toBeMergedVcfs,
                outputPath = SVdir + 'survivor/' + svtype + '.union.vcf',
                suppVecs = 1
        }

        call bcftools.View as getIntersections {
            input:
            dockerImage = dockerImages["bcftools"],
            inputFile = survivor.mergedVcf,
            outputPath = SVdir + 'survivor/' + svtype + '.isec.vcf',
            exclude = "'SUPP=\"1\"'"
        }
    }

    output {
        File cleverVcf = clever.predictions
        File mateCleverVcf = mateclever.matecleverVcf
        File mantaVcf = manta.mantaVCF
        File dellyVcf = delly2vcf.outputVcf
        File? smooveVcf = smoove.smooveVcf
        File gridssVcf = gridss.vcf
        File gridssVcfIndex = gridss.vcfIndex
        Array[Array[File]] modifiedVcfs = toBeMergedVcfs
        Array[File] unionVCFs = survivor.mergedVcf
        Array[File] isecVCFs = getIntersections.outputVcf

    }

    parameter_meta {
        outputDir: {description: "The directory the output should be written to.", category: "common"}
        referenceFasta: { description: "The reference fasta file", category: "required" }
        referenceFastaFai: { description: "Fasta index (.fai) file of the reference", category: "required" }
        referenceFastaDict: { description: "Sequence dictionary (.dict) file of the reference", category: "required" }
        bamFile: {description: "sorted BAM file", category: "required"}
        bamIndex: {description: "BAM index(.bai) file", category: "required"}
        bwaIndex: {description: "Struct containing the BWA reference files", category: "required"}
        sample: {description: "The name of the sample", category: "required"}
        runDupHold: {description: "Option to run duphold annotation and filter FP deletions and duplications.", category: "advanced"}
        runSmoove: {description: "Whether or not to run smoove.", category: "advanced"}
        excludeMisHomRef: {description: "Option to exclude missing and homozygous reference genotypes.", category: "advanced"}
        svtypes: {description: "List of svtypes to be further processed and output by the pipeline.", category: "advanced"}
        dockerImages: {description: "A map describing the docker image used for the tasks.",
                           category: "advanced"}
    }
}
